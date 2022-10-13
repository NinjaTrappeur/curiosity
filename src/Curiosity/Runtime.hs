{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE GeneralisedNewtypeDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE TypeFamilies #-}
-- brittany-disable-next-binding
module Curiosity.Runtime
  ( IOErr(..)
  , UnspeciedErr(..)
  , Runtime(..)
  , rConf
  , rDb
  , rLoggers
  , AppM(..)
  , RunM(..)
  , boot
  , boot'
  , reset
  , state
  , handleCommand
  , submitQuotationSuccess
  , powerdown
  , readDb
  , readDbSafe
  , saveDb
  , saveDbAs
  , runAppMSafe
  , runRunM
  , withRuntimeAtomically
  -- * High-level user operations
  , setUserEmailAddrAsVerifiedFull
  , selectUserByIdResolved
  , selectUserByUsername
  , selectUserByUsernameResolved
  , filterUsers
  , createUser
  , checkCredentials
  -- * High-level entity operations
  , selectEntityBySlug
  , selectEntityBySlugResolved
  , selectEntitiesWhereUserId
  , readLegalEntities
  -- * High-level unit operations
  , selectUnitBySlug
  -- * Form edition
  -- ** Quotation
  , formNewQuotation'
  , readCreateQuotationForm'
  , readCreateQuotationForms'
  , writeCreateQuotationForm
  , submitCreateQuotationForm
  -- ** Contract
  , newCreateContractForm
  , readCreateContractForm
  , writeCreateContractForm
  , addExpenseToContractForm
  , writeExpenseToContractForm
  , removeExpenseFromContractForm
  -- ** Simple Contract
  , newCreateSimpleContractForm
  , readCreateSimpleContractForm
  , writeCreateSimpleContractForm
  , addRoleToSimpleContractForm
  , addDateToSimpleContractForm
  , writeDateToSimpleContractForm
  , removeDateFromSimpleContractForm
  , addVATToSimpleContractForm
  , addExpenseToSimpleContractForm
  , writeExpenseToSimpleContractForm
  , removeExpenseFromSimpleContractForm
  -- * Servant compat
  , appMHandlerNatTrans
  ) where

import qualified Commence.Multilogging         as ML
import qualified Commence.Runtime.Errors       as Errs
import qualified Commence.Runtime.Storage      as S
import           Commence.Types.Secret          ( (=:=) )
import qualified Control.Concurrent.STM        as STM
import           Control.Lens                  as Lens
import "exceptions" Control.Monad.Catch         ( MonadCatch
                                                , MonadMask
                                                , MonadThrow
                                                )
import qualified Curiosity.Command             as Command
import qualified Curiosity.Core                as Core
import qualified Curiosity.Data                as Data
import qualified Curiosity.Data.Business       as Business
import qualified Curiosity.Data.Email          as Email
import qualified Curiosity.Data.Employment     as Employment
import qualified Curiosity.Data.Invoice        as Invoice
import qualified Curiosity.Data.Legal          as Legal
import qualified Curiosity.Data.Order          as Order
import qualified Curiosity.Data.Quotation      as Quotation
import qualified Curiosity.Data.RemittanceAdv  as RemittanceAdv
import qualified Curiosity.Data.SimpleContract as SimpleContract
import qualified Curiosity.Data.User           as User
import qualified Curiosity.Parse               as Command
import qualified Data.Aeson.Text               as Aeson
import qualified Data.ByteString.Lazy          as BS
import           Data.List                      ( lookup )
import qualified Data.Map                      as M
import qualified Data.Text                     as T
import qualified Data.Text.Encoding            as TE
import qualified Data.Text.IO                  as T
import qualified Data.Text.Lazy                as LT
import qualified Network.HTTP.Types            as HTTP
import           Prelude                 hiding ( state )
import qualified Servant
import           System.Directory               ( doesFileExist )


--------------------------------------------------------------------------------
-- | The runtime, a central product type that should contain all our runtime
-- supporting values: the STM state, and loggers.
data Runtime = Runtime
  { _rConf    :: Command.Conf -- ^ The application configuration.
  , _rDb      :: Core.StmDb Runtime -- ^ The Storage.
  , _rLoggers :: ML.AppNameLoggers -- ^ Multiple loggers to log over.
  }

makeLenses ''Runtime


--------------------------------------------------------------------------------
newtype AppM a = AppM { runAppM :: ReaderT Runtime (ExceptT Errs.RuntimeErr IO) a }
  deriving ( Functor
           , Applicative
           , Monad
           , MonadIO
           , MonadReader Runtime
           , MonadError Errs.RuntimeErr
           , MonadThrow
           , MonadCatch
           , MonadMask
           )

-- | Run the `AppM` computation catching all possible exceptions.
runAppMSafe
  :: forall a m
   . MonadIO m
  => Runtime
  -> AppM a
  -> m (Either Errs.RuntimeErr a)
runAppMSafe runtime AppM {..} =
  liftIO
    . fmap (join . first Errs.RuntimeException)
    . try @SomeException
    . runExceptT
    $ runReaderT runAppM runtime

-- | `RunM` is basically STM operations (from `Curiosity.Core`) together with
-- the ability to do IO for logging.
newtype RunM a = RunM { unRunM :: ReaderT Runtime IO a }
  deriving ( Functor
           , Applicative
           , Monad
           , MonadIO
           , MonadReader Runtime
           , MonadError IOException
           , MonadThrow
           , MonadCatch
           , MonadMask
           )

runRunM :: forall a m . MonadIO m => Runtime -> RunM a -> m a
runRunM runtime RunM {..} = liftIO $ runReaderT unRunM runtime

-- | Support for logging for the application
instance ML.MonadAppNameLogMulti RunM where
  askLoggers = asks _rLoggers
  localLoggers modLogger =
    local (over rLoggers . over ML.appNameLoggers $ fmap modLogger)


--------------------------------------------------------------------------------
-- | Boot up a runtime.
boot
  :: MonadIO m
  => Command.Conf -- ^ configuration to boot with.
  -> m (Either Errs.RuntimeErr Runtime)
boot _rConf =
  liftIO
      (  try @SomeException
      .  ML.makeDefaultLoggersWithConf
      $  _rConf
      ^. Command.confLogging
      )
    >>= \case
          Left loggerErrs ->
            putStrLn @Text
                (  "Cannot instantiate, logger instantiation failed: "
                <> show loggerErrs
                )
              $> Left (Errs.RuntimeException loggerErrs)
          Right _rLoggers -> do
            eDb <- instantiateDb _rConf
            pure $ case eDb of
              Left  err  -> Left err
              Right _rDb -> Right Runtime { .. }

-- | Create a runtime from a given state.
boot' :: MonadIO m => Data.HaskDb Runtime -> FilePath -> m Runtime
boot' db logsPath = do
  let loggingConf = Command.mkLoggingConf logsPath
      _rConf      = Command.defaultConf { Command._confLogging = loggingConf }
  _rDb      <- liftIO . STM.atomically $ Core.instantiateStmDb db
  _rLoggers <- ML.makeDefaultLoggersWithConf loggingConf
  pure $ Runtime { .. }

-- | Reset the database to the empty state.
reset :: RunM ()
reset = do
  ML.localEnv (<> "Command" <> "Reset")
    $ ML.info
    $ "Resetting to the empty state."
  db <- asks _rDb
  liftIO . STM.atomically $ Core.reset db

-- | Reads all values of the `Db` product type from `STM.STM` to @Hask@.
readFullStmDbInHask
  :: forall runtime m . MonadIO m => Core.StmDb runtime -> m (Data.HaskDb runtime)
readFullStmDbInHask = liftIO . STM.atomically . Core.readFullStmDbInHask'

-- | Power down the application: attempting to save the DB state in given file,
-- if possible, and reporting errors otherwise.
powerdown :: MonadIO m => Runtime -> m (Maybe Errs.RuntimeErr)
powerdown runtime@Runtime {..} = do
  mDbSaveErr <- saveDb runtime
  reportDbSaveErr mDbSaveErr
  -- finally, close loggers.
  eLoggingCloseErrs <- liftIO . try @SomeException $ ML.flushAndCloseLoggers
    _rLoggers
  reportLoggingCloseErrs eLoggingCloseErrs
  pure $ mDbSaveErr <|> first Errs.RuntimeException eLoggingCloseErrs ^? _Left
 where
  reportLoggingCloseErrs eLoggingCloseErrs =
    when (isLeft eLoggingCloseErrs)
      .  putStrLn @Text
      $  "Errors when closing loggers: "
      <> show eLoggingCloseErrs
  reportDbSaveErr mDbSaveErr =
    when (isJust mDbSaveErr)
      .  putStrLn @Text
      $  "DB state cannot be saved: "
      <> show mDbSaveErr

saveDb :: MonadIO m => Runtime -> m (Maybe Errs.RuntimeErr)
saveDb runtime =
  maybe (pure Nothing) (saveDbAs runtime) $ _rConf runtime ^. Command.confDbFile

saveDbAs :: MonadIO m => Runtime -> FilePath -> m (Maybe Errs.RuntimeErr)
saveDbAs runtime fpath = do
  haskDb <- readFullStmDbInHask $ _rDb runtime
  let bs = Data.serialiseDb haskDb
  liftIO
      (try @SomeException (T.writeFile fpath . TE.decodeUtf8 $ BS.toStrict bs))
    <&> either (Just . Errs.RuntimeException) (const Nothing)

-- | Retrieve the whole state as a pure value.
state :: RunM (Data.HaskDb Runtime)
state = do
  db <- asks _rDb
  liftIO . STM.atomically $ Core.readFullStmDbInHask' db

{- | Instantiate the db.

1. The state is either the empty db, or if a _confDbFile file is specified, is
read from the file.

2. Whenever the application exits, the state is written to disk, if a
_confDbFile is specified.
-}
instantiateDb
  :: forall m
   . MonadIO m
  => Command.Conf
  -> m (Either Errs.RuntimeErr (Core.StmDb Runtime))
instantiateDb Command.Conf {..} = readDbSafe _confDbFile

readDb
  :: forall m
   . MonadIO m
  => Maybe FilePath
  -> m (Either Errs.RuntimeErr (Core.StmDb Runtime))
readDb mpath = case mpath of
  Just fpath -> do
    -- We may want to read the file only when the file exists.
    exists <- liftIO $ doesFileExist fpath
    if exists then fromFile fpath else useEmpty
  Nothing -> useEmpty
 where
  fromFile fpath = liftIO (try @SomeException $ T.readFile fpath) >>= \case
    Left err ->
      putStrLn @Text ("Unable to read db file: " <> maybe "" T.pack mpath)
        $> Left (Errs.RuntimeException err)
    Right fdata ->
           -- We may want to deserialise the data only when the data is non-empty.
                   if T.null fdata
      then useEmpty
      else
        Data.deserialiseDbStrict (TE.encodeUtf8 fdata)
          & either (pure . Left . Errs.knownErr) useState
  useEmpty = Right <$> (liftIO $ STM.atomically Core.instantiateEmptyStmDb)
  useState = fmap Right . liftIO . STM.atomically . Core.instantiateStmDb

-- | A safer version of readDb: this fails if the file doesn't exist or is
-- empty. This helps in catching early mistake, e.g. from user specifying the
-- wrong file name on the command-line.
readDbSafe
  :: forall m
   . MonadIO m
  => Maybe FilePath
  -> m (Either Errs.RuntimeErr (Core.StmDb Runtime))
readDbSafe mpath = case mpath of
  Just fpath -> do
    -- We may want to read the file only when the file exists.
    exists <- liftIO $ doesFileExist fpath
    if exists
      then fromFile fpath
      else pure . Left . Errs.knownErr $ FileDoesntExistErr fpath
  Nothing -> useEmpty
 where
  fromFile fpath = do
    fdata <- liftIO (T.readFile fpath)
    Data.deserialiseDbStrict (TE.encodeUtf8 fdata)
      & either (pure . Left . Errs.knownErr) useState
  useEmpty = Right <$> (liftIO $ STM.atomically Core.instantiateEmptyStmDb)
  useState = fmap Right . liftIO . STM.atomically . Core.instantiateStmDb

-- | Natural transformation from some `AppM` in any given mode, to a servant
-- Handler.
appMHandlerNatTrans :: forall a . Runtime -> AppM a -> Servant.Handler a
appMHandlerNatTrans rt appM =
  let
      -- We peel off the AppM + ReaderT layers, exposing our ExceptT
      -- RuntimeErr IO a This is very similar to Servant's Handler:
      -- https://hackage.haskell.org/package/servant-server-0.17/docs/Servant-Server-Internal-Handler.html#t:Handler
      unwrapReaderT          = (`runReaderT` rt) . runAppM $ appM
      -- Map our errors to `ServantError`
      runtimeErrToServantErr = withExceptT Errs.asServantError
  in
      -- Re-wrap as servant `Handler`
      Servant.Handler $ runtimeErrToServantErr unwrapReaderT


--------------------------------------------------------------------------------
-- | Support for logging for the application
instance ML.MonadAppNameLogMulti AppM where
  askLoggers = asks _rLoggers
  localLoggers modLogger =
    local (over rLoggers . over ML.appNameLoggers $ fmap modLogger)


--------------------------------------------------------------------------------
-- | Handle a single command. The return type provides some flexibility, so
-- this function can be used in both `cty` and `cty repl`.
handleCommand
  :: MonadIO m
  => Runtime
  -> User.UserName -- ^ The user performing the command.
  -> Command.Command
  -> m (ExitCode, [Text])
handleCommand runtime@Runtime {..} user command = do
  case command of
    Command.State useHs -> do
      value <- runRunM runtime state
      let value' = if useHs
            then show value
            else LT.toStrict (Aeson.encodeToLazyText value)
      pure (ExitSuccess, [value'])
    Command.CreateBusinessEntity input -> do
      output <- runAppMSafe runtime . liftIO . STM.atomically $ Core.createBusiness
        _rDb
        input
      case output of
        Right mid -> do
          case mid of
            Right (Business.UnitId id) -> do
              pure (ExitSuccess, ["Business entity created: " <> id])
            Left err -> pure (ExitFailure 1, [show err])
        Left err -> pure (ExitFailure 1, [show err])
    Command.UpdateBusinessEntity input -> do
      output <- runAppMSafe runtime . liftIO . STM.atomically $ Core.updateBusiness
        _rDb
        input
      case output of
        Right mid -> do
          case mid of
            Right () -> do
              pure
                ( ExitSuccess
                , ["Business unit updated: " <> Business._updateSlug input]
                )
            Left err -> pure (ExitFailure 1, [show err])
        Left err -> pure (ExitFailure 1, [show err])
    Command.CreateLegalEntity input -> do
      output <- runAppMSafe runtime . liftIO . STM.atomically $ createLegal
        _rDb
        input
      case output of
        Right mid -> do
          case mid of
            Right (Legal.EntityId id) -> do
              pure (ExitSuccess, ["Legal entity created: " <> id])
            Left err -> pure (ExitFailure 1, [show err])
        Left err -> pure (ExitFailure 1, [show err])
    Command.UpdateLegalEntity input -> do
      output <- runAppMSafe runtime . liftIO . STM.atomically $ updateLegal
        _rDb
        input
      case output of
        Right mid -> do
          case mid of
            Right () -> do
              pure
                ( ExitSuccess
                , ["Legal entity updated: " <> Legal._updateSlug input]
                )
            Left err -> pure (ExitFailure 1, [show err])
        Left err -> pure (ExitFailure 1, [show err])
    Command.CreateUser input -> do
      muid <- runRunM runtime $ createUser input
      case muid of
        Right (User.UserId uid) ->
          pure (ExitSuccess, ["User created: " <> uid])
        Left err -> pure (ExitFailure 1, [show err])
    Command.SelectUser useHs uid short -> do
      output <-
        runAppMSafe runtime . liftIO . STM.atomically $ Core.selectUserById
          _rDb
          uid
      case output of
        Right mprofile -> do
          case mprofile of
            Just value -> do
              let value' = if useHs
                    then show value
                    else LT.toStrict (Aeson.encodeToLazyText value)
              if short
                then pure
                  ( ExitSuccess
                  , [ User.unUserId (User._userProfileId value)
                      <> " "
                      <> User.unUserName
                           (User._userCredsName $ User._userProfileCreds value)
                    ]
                  )
                else pure (ExitSuccess, [value'])
            Nothing -> pure (ExitFailure 1, ["No such user."])
        Left err -> pure (ExitFailure 1, [show err])
    Command.FilterUsers predicate -> do
      output <- runAppMSafe runtime
        $ withRuntimeAtomically filterUsers predicate
      case output of
        Right profiles -> do
          let f User.UserProfile {..} =
                let User.UserId   i = _userProfileId
                    User.UserName n = User._userCredsName _userProfileCreds
                in  i <> " " <> n
          pure (ExitSuccess, map f profiles)
        Left err -> pure (ExitFailure 1, [show err])
    Command.UpdateUser input -> do
      output <-
        runAppMSafe runtime . S.liftTxn @AppM @STM $ S.dbUpdate @AppM @STM
          _rDb
          input
      case output of
        Right mid -> do
          case mid of
            Right storageResult -> do
              case storageResult of
                Right [uid] ->
                  pure (ExitSuccess, ["User updated: " <> User.unUserId uid])
                Right _   -> pure (ExitFailure 1, ["No record updated."])
                Left  err -> pure (ExitFailure 1, [show err])
            Left err -> pure (ExitFailure 1, [show err])
        Left err -> pure (ExitFailure 1, [show err])
    Command.SetUserEmailAddrAsVerified username -> do
      output <-
        runAppMSafe runtime
        .   liftIO
        .   STM.atomically
        $   Core.selectUserByUsername _rDb user
        >>= \case
              Just profile ->
                setUserEmailAddrAsVerifiedFull _rDb (profile, username)
              Nothing -> pure . Left . User.UserNotFound $ User.unUserName user
      case output of
        Right (Right ()) -> do
          pure (ExitSuccess, ["User successfully updated."])
        Right (Left err) -> pure (ExitFailure 1, [show err])
        Left  err        -> pure (ExitFailure 1, [show err])
    Command.CreateEmployment input -> do
      output <-
        runAppMSafe runtime
        .   liftIO
        .   STM.atomically
        $   Core.selectUserByUsername _rDb user
        >>= \case
              Just profile -> do
                merror <- submitCreateContractForm' _rDb (profile, input)
                -- TODO Should we have a type to combine multiple possible errors ?
                case merror of
                  Left (Employment.Err err) ->
                    pure . Left $ User.UserNotFound err
                  Right id -> pure $ Right id
              Nothing -> pure . Left . User.UserNotFound $ User.unUserName user
      case output of
        Right mid -> do
          case mid of
            Right (Employment.ContractId id) -> do
              pure (ExitSuccess, ["Employment contract created: " <> id])
            Left err -> pure (ExitFailure 1, [show err])
        Left err -> pure (ExitFailure 1, [show err])
    Command.CreateInvoice -> do
      output <- runAppMSafe runtime . liftIO . STM.atomically $ createInvoice
        _rDb
      case output of
        Right mid -> do
          case mid of
            Right (Invoice.InvoiceId id) -> do
              pure (ExitSuccess, ["Invoice created: " <> id])
            Left err -> pure (ExitFailure 1, [show err])
        Left err -> pure (ExitFailure 1, [show err])
    Command.FormNewQuotation input -> do
      mkey <- runRunM runtime $ formNewQuotation user input
      case mkey of
        Right key -> do
          pure (ExitSuccess, ["Quotation form created: " <> key])
        Left err -> pure (ExitFailure 1, [show err])
    Command.FormValidateQuotation input ->
      liftIO . STM.atomically $ Core.selectUserByUsername _rDb user >>= \case
        Just profile -> do
          mcontract <- readCreateQuotationForm _rDb (profile, input)
          case mcontract of
            Right contract -> do
              case Quotation.validateCreateQuotation profile contract of
                Right _    -> pure (ExitSuccess, ["Quotation form is valid."])
                Left  errs -> pure (ExitFailure 1, map Quotation.unErr errs)
            Left _ -> pure (ExitFailure 1, ["Key not found: " <> input])
        Nothing ->
          pure (ExitFailure 1, ["Username not found: " <> User.unUserName user])
    Command.FormSubmitQuotation input ->
      liftIO . STM.atomically $ Core.selectUserByUsername _rDb user >>= \case
        Just profile -> do
          mid <- submitCreateQuotationForm _rDb (profile, input)
          case mid of
            Right id -> pure
              ( ExitSuccess
              , submitQuotationSuccess id
              )
            Left err -> pure (ExitFailure 1, [Quotation.unErr err])
        Nothing ->
          pure (ExitFailure 1, ["Username not found: " <> User.unUserName user])
    Command.SignQuotation input ->
      liftIO . STM.atomically $ Core.selectUserByUsername _rDb user >>= \case
        Just profile -> do
          mid <- signQuotation _rDb (profile, input)
          case mid of
            Right id ->
              pure (ExitSuccess, ["Order created: " <> Order.unOrderId id])
            Left err -> pure (ExitFailure 1, [Quotation.unErr err])
        Nothing ->
          pure (ExitFailure 1, ["Username not found: " <> User.unUserName user])
    Command.EmitInvoice input ->
      liftIO . STM.atomically $ Core.selectUserByUsername _rDb user >>= \case
        Just profile -> do
          mids <- invoiceOrder _rDb (profile, input)
          case mids of
            Right (id0, id1, id2, id3) -> pure
              ( ExitSuccess
              , [ "Invoice created: " <> Invoice.unInvoiceId id0
                , "Internal (proxy) invoice created: "
                  <> Invoice.unInvoiceId id1
                , "Generating payment for " <> Invoice.unInvoiceId id1 <> "..."
                , "Remittance advice (using proxy bank account) created: "
                  <> RemittanceAdv.unRemittanceAdvId id2
                , "Remittance advice (using business unit bank account) created: "
                  <> RemittanceAdv.unRemittanceAdvId id3
                , "Invoice sent to client: " <> Invoice.unInvoiceId id0
                ]
              )
            Left err -> pure (ExitFailure 1, [Order.unErr err])
        Nothing ->
          pure (ExitFailure 1, ["Username not found: " <> User.unUserName user])
    Command.SendReminder input ->
      -- TODO Check this is the "system" user ?
                                  liftIO . STM.atomically $ do
      createEmail _rDb Email.InvoiceReminderEmail "TODO client email addr"
      pure
        ( ExitSuccess
        , ["Reminder for invoice sent: " <> Invoice.unInvoiceId input]
        )
    Command.MatchPayment input ->
      -- TODO Check this is the "system" user ?
                                  liftIO . STM.atomically $ do
      mids <- matchPayment _rDb input
      case mids of
        Right (id0, id1) -> pure
          ( ExitSuccess
          , [ "Generating payment for " <> Invoice.unInvoiceId input <> "..."
            , "Remittance advice (using client bank account) created: "
              <> RemittanceAdv.unRemittanceAdvId id0
            , "Remittance advice (using business unit bank account) created: "
              <> RemittanceAdv.unRemittanceAdvId id1
            ]
          )
        Left err -> pure (ExitFailure 1, [Invoice.unErr err])
    Command.FormNewSimpleContract input -> do
      output <-
        runAppMSafe runtime
        .   liftIO
        .   STM.atomically
        $   Core.selectUserByUsername _rDb user
        >>= \case
              Just profile -> do
                key <- newCreateSimpleContractForm _rDb (profile, input)
                pure $ Right key
              Nothing -> pure . Left . User.UserNotFound $ User.unUserName user
      case output of
        Right mkey -> do
          case mkey of
            Right key -> do
              pure (ExitSuccess, ["Simple contract form created: " <> key])
            Left err -> pure (ExitFailure 1, [show err])
        Left err -> pure (ExitFailure 1, [show err])
    Command.FormValidateSimpleContract input ->
      liftIO . STM.atomically $ Core.selectUserByUsername _rDb user >>= \case
        Just profile -> do
          mcontract <- readCreateSimpleContractForm _rDb (profile, input)
          case mcontract of
            Right contract -> do
              case
                  SimpleContract.validateCreateSimpleContract profile contract
                of
                  Right _ ->
                    pure (ExitSuccess, ["Simple contract form is valid."])
                  Left errs ->
                    pure (ExitFailure 1, map SimpleContract.unErr errs)
            Left _ -> pure (ExitFailure 1, ["Key not found: " <> input])
        Nothing ->
          pure (ExitFailure 1, ["Username not found: " <> User.unUserName user])
    Command.Step -> do
      let transaction rt _ = do
            users <- filterUsers rt User.PredicateEmailAddrToVerify
            mapM
              ( setUserEmailAddrAsVerified _rDb
              . User._userCredsName
              . User._userProfileCreds
              )
              users
      output <- runAppMSafe runtime $ withRuntimeAtomically transaction ()
      case output of
        Right x   -> pure (ExitSuccess, map show x)
        Left  err -> pure (ExitFailure 1, [Errs.displayErr err])
    _ -> do
      -- TODO It seems that showing the command causes a stack overflow. For
      -- instance the error happens by passing the Log or the Reset commands.
      -- I think this has to do with the fact that they contain a conf.
      -- pure (ExitFailure 1, ["Unhandled command " <> show command])
      pure (ExitFailure 1, ["Unhandled command."])

submitQuotationSuccess id =
  [ "Quotation form validated."
  , "Quotation created: " <> Quotation.unQuotationId id
  , "Quotation sent to client: " <> Quotation.unQuotationId id
  ]

setUserEmailAddrAsVerifiedFull
  :: Core.StmDb runtime
  -> (User.UserProfile, User.UserName)
  -> STM (Either User.UserErr ())
setUserEmailAddrAsVerifiedFull db (user, input) = transaction
 where
  transaction = do
    b <- Core.canPerform 'User.SetUserEmailAddrAsVerified db user
    if b
      then setUserEmailAddrAsVerified db input
      else pure . Left $ User.MissingRight User.CanVerifyEmailAddr

instance S.DBTransaction AppM STM where
  liftTxn =
    liftIO
      . fmap (first Errs.RuntimeException)
      . try @SomeException
      . STM.atomically


--------------------------------------------------------------------------------
createLegal
  :: forall runtime
   . Core.StmDb runtime
  -> Legal.Create
  -> STM (Either Legal.Err Legal.EntityId)
createLegal db Legal.Create {..} = do
  STM.catchSTM (Right <$> transaction) (pure . Left)
 where
  transaction = do
    newId <- Core.generateLegalId db
    let new = Legal.Entity newId
                           _createSlug
                           _createName
                           _createCbeNumber
                           _createVatNumber
                           Nothing
                           []
    createLegalFull db new >>= either STM.throwSTM pure

createLegalFull
  :: forall runtime
   . Core.StmDb runtime
  -> Legal.Entity
  -> STM (Either Legal.Err Legal.EntityId)
createLegalFull db new = do
  modifyLegalEntities db (++ [new])
  pure . Right $ Legal._entityId new

updateLegal db Legal.Update {..} = do
  mentity <- selectEntityBySlug db _updateSlug
  case mentity of
    Just Legal.Entity{} -> do
      let replaceOlder entities =
            [ if Legal._entitySlug e == _updateSlug
                then e { Legal._entityDescription = _updateDescription }
                else e
            | e <- entities
            ]
      modifyLegalEntities db replaceOlder
      pure $ Right ()
    Nothing -> pure . Left $ User.UserNotFound _updateSlug -- TODO

modifyLegalEntities
  :: forall runtime
   . Core.StmDb runtime
  -> ([Legal.Entity] -> [Legal.Entity])
  -> STM ()
modifyLegalEntities db f =
  let tvar = Data._dbLegalEntities db in STM.modifyTVar tvar f


--------------------------------------------------------------------------------
selectUnitBySlug :: Text -> RunM (Maybe Business.Unit)
selectUnitBySlug slug = do
  db <- asks _rDb
  liftIO . STM.atomically $ Core.selectUnitBySlug db slug


--------------------------------------------------------------------------------
createQuotation
  :: forall runtime
   . Core.StmDb runtime
  -> Quotation.Quotation
  -> STM (Either Quotation.Err Quotation.QuotationId)
createQuotation db _ = do
  STM.catchSTM (Right <$> transaction) (pure . Left)
 where
  transaction = do
    newId <- Core.generateQuotationId db
    let new = Quotation.Quotation newId
    createQuotationFull db new >>= either STM.throwSTM pure

createQuotationFull
  :: forall runtime
   . Core.StmDb runtime
  -> Quotation.Quotation
  -> STM (Either Quotation.Err Quotation.QuotationId)
createQuotationFull db new = do
  modifyQuotations db (++ [new])
  pure . Right $ Quotation._quotationId new

modifyQuotations
  :: forall runtime
   . Core.StmDb runtime
  -> ([Quotation.Quotation] -> [Quotation.Quotation])
  -> STM ()
modifyQuotations db f =
  let tvar = Data._dbQuotations db in STM.modifyTVar tvar f

signQuotation
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Quotation.QuotationId)
     -- ^ TODO SignQuotation data type, including e.g. the signature data.
  -> STM (Either Quotation.Err Order.OrderId)
signQuotation db _ = do
  mid <- createOrder db
  case mid of
    Right id              -> pure $ Right id
    Left  (Order.Err err) -> pure $ Left $ Quotation.Err err


--------------------------------------------------------------------------------
createOrder
  :: forall runtime . Core.StmDb runtime -> STM (Either Order.Err Order.OrderId)
createOrder db = do
  STM.catchSTM (Right <$> transaction) (pure . Left)
 where
  transaction = do
    newId <- Core.generateOrderId db
    let new = Order.Order newId
    createOrderFull db new >>= either STM.throwSTM pure

createOrderFull
  :: forall runtime
   . Core.StmDb runtime
  -> Order.Order
  -> STM (Either Order.Err Order.OrderId)
createOrderFull db new = do
  modifyOrders db (++ [new])
  pure . Right $ Order._orderId new

modifyOrders
  :: forall runtime
   . Core.StmDb runtime
  -> ([Order.Order] -> [Order.Order])
  -> STM ()
modifyOrders db f = let tvar = Data._dbOrders db in STM.modifyTVar tvar f

invoiceOrder
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Order.OrderId)
  -> STM
       ( Either
           Order.Err
           ( Invoice.InvoiceId
           , Invoice.InvoiceId
           , RemittanceAdv.RemittanceAdvId
           , RemittanceAdv.RemittanceAdvId
           )
       )
invoiceOrder db (profile, _) = do
  mids <- STM.catchSTM (Right <$> createTwoInvoices db) (pure . Left)
  case mids of
    Right (id0, id1, id2, id3) -> do
      -- Invoices and remittance advices created, do the rest of the atomic process.
      createEmail db Email.InvoiceEmail $ User._userProfileEmailAddr profile
      -- TODO The email address should be the one from the client.
      pure $ Right (id0, id1, id2, id3)
    Left (Invoice.Err err) -> pure $ Left $ Order.Err err

createTwoInvoices db = do
  mid0 <- createInvoice db
  mid1 <- createInvoice db
  mid2 <- createRemittanceAdv db
  mid3 <- createRemittanceAdv db
  case (mid0, mid1, mid2, mid3) of
    (Right id0, Right id1, Right id2, Right id3) -> pure (id0, id1, id2, id3)
    _ -> STM.throwSTM $ Invoice.Err "Failed to create invoices."


--------------------------------------------------------------------------------
createRemittanceAdv
  :: forall runtime
   . Core.StmDb runtime
  -> STM (Either RemittanceAdv.Err RemittanceAdv.RemittanceAdvId)
createRemittanceAdv db = do
  STM.catchSTM (Right <$> transaction) (pure . Left)
 where
  transaction = do
    newId <- Core.generateRemittanceAdvId db
    let new = RemittanceAdv.RemittanceAdv newId
    createRemittanceAdvFull db new >>= either STM.throwSTM pure

createRemittanceAdvFull
  :: forall runtime
   . Core.StmDb runtime
  -> RemittanceAdv.RemittanceAdv
  -> STM (Either RemittanceAdv.Err RemittanceAdv.RemittanceAdvId)
createRemittanceAdvFull db new = do
  modifyRemittanceAdvs db (++ [new])
  pure . Right $ RemittanceAdv._remittanceAdvId new

modifyRemittanceAdvs
  :: forall runtime
   . Core.StmDb runtime
  -> ([RemittanceAdv.RemittanceAdv] -> [RemittanceAdv.RemittanceAdv])
  -> STM ()
modifyRemittanceAdvs db f =
  let tvar = Data._dbRemittanceAdvs db in STM.modifyTVar tvar f


--------------------------------------------------------------------------------
createEmployment
  :: forall runtime
   . Core.StmDb runtime
  -> Employment.Contract
  -> STM (Either Employment.Err Employment.ContractId)
createEmployment db _ = do
  STM.catchSTM (Right <$> transaction) (pure . Left)
 where
  transaction = do
    newId <- Core.generateEmploymentId db
    let new = Employment.Contract newId
    createEmploymentFull db new >>= either STM.throwSTM pure

createEmploymentFull
  :: forall runtime
   . Core.StmDb runtime
  -> Employment.Contract
  -> STM (Either Employment.Err Employment.ContractId)
createEmploymentFull db new = do
  modifyEmployments db (++ [new])
  pure . Right $ Employment._contractId new

modifyEmployments
  :: forall runtime
   . Core.StmDb runtime
  -> ([Employment.Contract] -> [Employment.Contract])
  -> STM ()
modifyEmployments db f =
  let tvar = Data._dbEmployments db in STM.modifyTVar tvar f

newCreateContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Employment.CreateContractAll')
  -> STM Text
newCreateContractForm db (profile, Employment.CreateContractAll' gi ty ld rs inv)
  = do
    key <- Core.genRandomText db
    STM.modifyTVar (Data._dbFormCreateContractAll db) (add key)
    pure key
 where
  add key =
    M.insert (username, key) (Employment.CreateContractAll gi ty ld rs inv [])
  username = User._userCredsName $ User._userProfileCreds profile

readCreateContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text)
  -> STM (Either () Employment.CreateContractAll)
readCreateContractForm db (profile, key) = do
  m <- STM.readTVar $ Data._dbFormCreateContractAll db
  let mform = M.lookup (username, key) m
  pure $ maybe (Left ()) Right mform
  where username = User._userCredsName $ User._userProfileCreds profile

writeCreateContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, Employment.CreateContractAll')
  -> STM Text
writeCreateContractForm db (profile, key, Employment.CreateContractAll' gi ty ld rs inv)
  = do
    STM.modifyTVar (Data._dbFormCreateContractAll db) save
    pure key
 where
  -- TODO Return an error when the key is not found.
  save = M.adjust
    (\(Employment.CreateContractAll _ _ _ _ _ es) ->
      Employment.CreateContractAll gi ty ld rs inv es
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

addExpenseToContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, Employment.AddExpense)
  -> STM () -- TODO Possible errors
addExpenseToContractForm db (profile, key, expense) = do
  STM.modifyTVar (Data._dbFormCreateContractAll db) save
 where
  save = M.adjust
    (\(Employment.CreateContractAll gi ty ld rs inv es) ->
      Employment.CreateContractAll gi ty ld rs inv $ es ++ [expense]
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

writeExpenseToContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, Int, Employment.AddExpense)
  -> STM () -- TODO Possible errors
writeExpenseToContractForm db (profile, key, idx, expense) = do
  STM.modifyTVar (Data._dbFormCreateContractAll db) save
 where
  save = M.adjust
    (\(Employment.CreateContractAll gi ty ld rs inv es) ->
      let f i e = if i == idx then expense else e
          es' = zipWith f [0 ..] es
      in  Employment.CreateContractAll gi ty ld rs inv es'
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

removeExpenseFromContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, Int)
  -> STM () -- TODO Possible errors
removeExpenseFromContractForm db (profile, key, idx) = do
  STM.modifyTVar (Data._dbFormCreateContractAll db) save
 where
  save = M.adjust
    (\(Employment.CreateContractAll gi ty ld rs inv es) ->
      let es' = map snd . filter ((/= idx) . fst) $ zip [0 ..] es
      in  Employment.CreateContractAll gi ty ld rs inv es'
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

-- | Fetch the contract form from the staging area, then attempt to validate
-- and create it.
submitCreateContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Employment.SubmitContract)
  -> STM (Either Employment.Err Employment.ContractId)
submitCreateContractForm db (profile, Employment.SubmitContract key) = do
  minput <- readCreateContractForm db (profile, key)
  case minput of
    Right input -> submitCreateContractForm' db (profile, input)
    Left  err   -> pure . Left $ Employment.Err (show err)

-- | Attempt to validate a contract form and create it.
submitCreateContractForm'
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Employment.CreateContractAll)
  -> STM (Either Employment.Err Employment.ContractId)
submitCreateContractForm' db (profile, input) = do
  let mc = Employment.validateCreateContract profile input
  case mc of
    Right c   -> createEmployment db c
    Left  err -> pure . Left $ Employment.Err (show err)


--------------------------------------------------------------------------------
-- | Create a new form instance in the staging area.
formNewQuotation
  :: User.UserName
  -> Quotation.CreateQuotationAll
  -> RunM (Either User.UserErr Text)
formNewQuotation user input =
  ML.localEnv (<> "Command" <> "FormNewQuotation") $ do
    ML.info $ "Instanciating new quotation form..."
    db   <- asks _rDb
    mkey <-
      liftIO . STM.atomically $ Core.selectUserByUsername db user >>= \case
        Just profile -> do
          key <- newCreateQuotationForm db (profile, input)
          pure $ Right key
        Nothing -> pure . Left . User.UserNotFound $ User.unUserName user
    case mkey of
      Left  err -> ML.info $ "Can't instantiate form: " <> show err
      Right key -> ML.info $ "Quotation form created: " <> key
    pure mkey

-- | Create a new form instance in the staging area.
-- TODO Refacto: this is the same as above, but using a profile, instead of a username.
formNewQuotation'
  :: User.UserProfile -> Quotation.CreateQuotationAll -> RunM Text
formNewQuotation' profile input =
  ML.localEnv (<> "Command" <> "FormNewQuotation") $ do
    ML.info $ "Instanciating new quotation form..."
    db  <- asks _rDb
    key <- liftIO . STM.atomically $ do
      newCreateQuotationForm db (profile, input)
    ML.info $ "Quotation form created: " <> key
    pure key

-- | Create a new form instance in the staging area.
newCreateQuotationForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Quotation.CreateQuotationAll)
  -> STM Text
newCreateQuotationForm db (profile, Quotation.CreateQuotationAll) = do
  key <- Core.genRandomText db
  STM.modifyTVar (Data._dbFormCreateQuotationAll db) (add key)
  pure key
 where
  add key = M.insert (username, key) Quotation.CreateQuotationAll
  username = User._userCredsName $ User._userProfileCreds profile

readCreateQuotationForm'
  :: User.UserProfile -> Text -> RunM (Either () Quotation.CreateQuotationAll)
readCreateQuotationForm' profile key = do
  db <- asks _rDb
  liftIO . STM.atomically $ readCreateQuotationForm db (profile, key)

readCreateQuotationForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text)
  -> STM (Either () Quotation.CreateQuotationAll)
readCreateQuotationForm = readForm Data._dbFormCreateQuotationAll

readCreateQuotationForms'
  :: User.UserProfile -> RunM (Either () [(Text, Quotation.CreateQuotationAll)])
readCreateQuotationForms' profile = do
  db <- asks _rDb
  liftIO . STM.atomically $ readCreateQuotationForms db profile

readCreateQuotationForms
  :: forall runtime
   . Core.StmDb runtime
  -> User.UserProfile
  -> STM (Either () [(Text, Quotation.CreateQuotationAll)])
readCreateQuotationForms = readForms Data._dbFormCreateQuotationAll

writeCreateQuotationForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, Quotation.CreateQuotationAll)
  -> STM Text
writeCreateQuotationForm db (profile, key, Quotation.CreateQuotationAll) = do
  STM.modifyTVar (Data._dbFormCreateQuotationAll db) save
  pure key
 where
  -- TODO Return an error when the key is not found.
  save = M.adjust
    (\(Quotation.CreateQuotationAll) -> Quotation.CreateQuotationAll)
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

deleteCreateQuotationForm
  :: forall runtime . Core.StmDb runtime -> (User.UserProfile, Text) -> STM () -- TODO Error
deleteCreateQuotationForm = deleteForm Data._dbFormCreateQuotationAll

-- | Fetch the quotation form from the staging area, then attempt to validate
-- and create it. If successfull, the form is deleted.
submitCreateQuotationForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Quotation.SubmitQuotation)
  -> STM (Either Quotation.Err Quotation.QuotationId)
submitCreateQuotationForm db (profile, Quotation.SubmitQuotation key) = do
  minput <- readCreateQuotationForm db (profile, key)
  case minput of
    Right input -> do
      mid <- submitCreateQuotationForm' db (profile, input)
      case mid of
        Right _ -> do
          -- Quotation created, do the rest of the atomic process.
          deleteCreateQuotationForm db (profile, key)
          createEmail db Email.QuotationEmail
            $ User._userProfileEmailAddr profile
          -- TODO The email address should be the one from the client.
          pure mid
        _ -> pure mid
    Left err -> pure . Left $ Quotation.Err (show err)

-- | Attempt to validate a quotation form and create it.
submitCreateQuotationForm'
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Quotation.CreateQuotationAll)
  -> STM (Either Quotation.Err Quotation.QuotationId)
submitCreateQuotationForm' db (profile, input) = do
  let mc = Quotation.validateCreateQuotation profile input
  case mc of
    Right c   -> createQuotation db c
    Left  err -> pure . Left $ Quotation.Err (show err)


--------------------------------------------------------------------------------
-- | Create a new form instance in the staging area.
newCreateSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, SimpleContract.CreateContractAll')
  -> STM Text
newCreateSimpleContractForm db (profile, SimpleContract.CreateContractAll' ty rs cl inv)
  = do
    key <- Core.genRandomText db
    STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) (add key)
    pure key
 where
  add key = M.insert (username, key)
                     (SimpleContract.CreateContractAll ty rs cl inv [] [])
  username = User._userCredsName $ User._userProfileCreds profile

readCreateSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text)
  -> STM (Either () SimpleContract.CreateContractAll)
readCreateSimpleContractForm = readForm Data._dbFormCreateSimpleContractAll

writeCreateSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, SimpleContract.CreateContractAll')
  -> STM Text
writeCreateSimpleContractForm db (profile, key, SimpleContract.CreateContractAll' ty rs cl inv)
  = do
    STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) save
    pure key
 where
  -- TODO Return an error when the key is not found.
  save = M.adjust
    (\(SimpleContract.CreateContractAll _ _ _ _ ds es) ->
      SimpleContract.CreateContractAll ty rs cl inv ds es
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

addRoleToSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, SimpleContract.SelectRole)
  -> STM () -- TODO Possible errors
addRoleToSimpleContractForm db (profile, key, SimpleContract.SelectRole role) =
  do
    STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) save
 where
  save = M.adjust
    (\(SimpleContract.CreateContractAll ty rs cl inv ds es) ->
      let ty' = ty { SimpleContract._createContractRole = role }
      in  SimpleContract.CreateContractAll ty' rs cl inv ds es
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

addDateToSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, SimpleContract.AddDate)
  -> STM () -- TODO Possible errors
addDateToSimpleContractForm db (profile, key, date) = do
  STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) save
 where
  save = M.adjust
    (\(SimpleContract.CreateContractAll ty rs cl inv ds es) ->
      SimpleContract.CreateContractAll ty rs cl inv (ds ++ [date]) es
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

writeDateToSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, Int, SimpleContract.AddDate)
  -> STM () -- TODO Possible errors
writeDateToSimpleContractForm db (profile, key, idx, date) = do
  STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) save
 where
  save = M.adjust
    (\(SimpleContract.CreateContractAll ty rs cl inv ds es) ->
      let f i e = if i == idx then date else e
          ds' = zipWith f [0 ..] ds
      in  SimpleContract.CreateContractAll ty rs cl inv ds' es
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

removeDateFromSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, Int)
  -> STM () -- TODO Possible errors
removeDateFromSimpleContractForm db (profile, key, idx) = do
  STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) save
 where
  save = M.adjust
    (\(SimpleContract.CreateContractAll ty rs cl inv ds es) ->
      let ds' = map snd . filter ((/= idx) . fst) $ zip [0 ..] ds
      in  SimpleContract.CreateContractAll ty rs cl inv ds' es
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

addVATToSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, SimpleContract.SelectVAT)
  -> STM () -- TODO Possible errors
addVATToSimpleContractForm db (profile, key, SimpleContract.SelectVAT rate) =
  do
    STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) save
 where
  save = M.adjust
    (\(SimpleContract.CreateContractAll ty rs cl inv ds es) ->
      let inv' = inv { SimpleContract._createContractVAT = rate }
      in  SimpleContract.CreateContractAll ty rs cl inv' ds es
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

addExpenseToSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, SimpleContract.AddExpense)
  -> STM () -- TODO Possible errors
addExpenseToSimpleContractForm db (profile, key, expense) = do
  STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) save
 where
  save = M.adjust
    (\(SimpleContract.CreateContractAll ty ld cl rs inv es) ->
      SimpleContract.CreateContractAll ty ld cl rs inv $ es ++ [expense]
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

writeExpenseToSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, Int, SimpleContract.AddExpense)
  -> STM () -- TODO Possible errors
writeExpenseToSimpleContractForm db (profile, key, idx, expense) = do
  STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) save
 where
  save = M.adjust
    (\(SimpleContract.CreateContractAll ty ld rs cl inv es) ->
      let f i e = if i == idx then expense else e
          es' = zipWith f [0 ..] es
      in  SimpleContract.CreateContractAll ty ld rs cl inv es'
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile

removeExpenseFromSimpleContractForm
  :: forall runtime
   . Core.StmDb runtime
  -> (User.UserProfile, Text, Int)
  -> STM () -- TODO Possible errors
removeExpenseFromSimpleContractForm db (profile, key, idx) = do
  STM.modifyTVar (Data._dbFormCreateSimpleContractAll db) save
 where
  save = M.adjust
    (\(SimpleContract.CreateContractAll ty ld rs cl inv es) ->
      let es' = map snd . filter ((/= idx) . fst) $ zip [0 ..] es
      in  SimpleContract.CreateContractAll ty ld rs cl inv es'
    )
    (username, key)
  username = User._userCredsName $ User._userProfileCreds profile


--------------------------------------------------------------------------------
createInvoice
  :: forall runtime
   . Core.StmDb runtime
  -> STM (Either Invoice.Err Invoice.InvoiceId)
createInvoice db = do
  STM.catchSTM (Right <$> transaction) (pure . Left)
 where
  transaction = do
    newId <- Core.generateInvoiceId db
    let new = Invoice.Invoice newId
    createInvoiceFull db new >>= either STM.throwSTM pure

createInvoiceFull
  :: forall runtime
   . Core.StmDb runtime
  -> Invoice.Invoice
  -> STM (Either Invoice.Err Invoice.InvoiceId)
createInvoiceFull db new = do
  modifyInvoices db (++ [new])
  pure . Right $ Invoice._entityId new

modifyInvoices
  :: forall runtime
   . Core.StmDb runtime
  -> ([Invoice.Invoice] -> [Invoice.Invoice])
  -> STM ()
modifyInvoices db f = let tvar = Data._dbInvoices db in STM.modifyTVar tvar f

matchPayment
  :: forall runtime
   . Core.StmDb runtime
  -> Invoice.InvoiceId
  -> STM
       ( Either
           Invoice.Err
           (RemittanceAdv.RemittanceAdvId, RemittanceAdv.RemittanceAdvId)
       )
matchPayment db _ = do
  mids <- STM.catchSTM (Right <$> createTwoRemittanceAdvs db) (pure . Left)
  pure mids

createTwoRemittanceAdvs db = do
  mid0 <- createRemittanceAdv db
  mid1 <- createRemittanceAdv db
  case (mid0, mid1) of
    (Right id0, Right id1) -> pure (id0, id1)
    _ -> STM.throwSTM $ Invoice.Err "Failed to create remittance advices."

--------------------------------------------------------------------------------
createEmail
  :: forall runtime
   . Core.StmDb runtime
  -> Email.EmailTemplate
  -> User.UserEmailAddr
  -> STM (Either Email.Err Email.EmailId)
createEmail db template emailAddr = do
  STM.catchSTM (Right <$> transaction) (pure . Left)
 where
  transaction = do
    newId <- Core.generateEmailId db
    let new = Email.Email newId template emailAddr
    createEmailFull db new >>= either STM.throwSTM pure

createEmailFull
  :: forall runtime
   . Core.StmDb runtime
  -> Email.Email
  -> STM (Either Email.Err Email.EmailId)
createEmailFull db new = do
  modifyEmails db (++ [new])
  pure . Right $ Email._emailId new

modifyEmails
  :: forall runtime
   . Core.StmDb runtime
  -> ([Email.Email] -> [Email.Email])
  -> STM ()
modifyEmails db f = let tvar = Data._dbEmails db in STM.modifyTVar tvar f


--------------------------------------------------------------------------------
-- | Definition of all operations for the UserProfiles (selects and updates)
instance S.DBStorage AppM STM User.UserProfile where

  type Db AppM STM User.UserProfile = Core.StmDb Runtime

  type DBError AppM STM User.UserProfile = User.UserErr

  dbUpdate db@Data.Db {..} = \case

    User.UserCreate input -> second pure <$> Core.createUserFull db input

    User.UserCreateGeneratingUserId input ->
      second pure <$> Core.createUser db input

    User.UserDelete id ->
      S.dbSelect @AppM @STM db (User.SelectUserById id) <&> headMay >>= maybe
        (pure . userNotFound $ show id)
        (fmap Right . deleteUser)
     where
      deleteUser _ =
        modifyUserProfiles id (filter $ (/= id) . S.dbId) _dbUserProfiles

    User.UserUpdate id (User.Update mname mbio) ->
      S.dbSelect @AppM @STM db (User.SelectUserById id) <&> headMay >>= maybe
        (pure . userNotFound $ show id)
        (fmap Right . updateUser)
     where
      updateUser _ = modifyUserProfiles id replaceOlder _dbUserProfiles
      change =
        set User.userProfileBio mbio . set User.userProfileDisplayName mname
      replaceOlder users =
        [ if S.dbId u == id then change u else u | u <- users ]

  dbSelect db = \case

    User.UserLoginWithUserName input -> toList <$> checkCredentials db input

    User.SelectUserById        id    -> toList <$> Core.selectUserById db id

    User.SelectUserByUserName username ->
      toList <$> Core.selectUserByUsername db username

modifyUserProfiles id f userProfiles = STM.modifyTVar userProfiles f $> [id]

selectUserByIdResolved db id = do
  let usersTVar = Data._dbUserProfiles db
  users' <- STM.readTVar usersTVar
  case find ((== id) . S.dbId) users' of
    Just user -> do
      entities <- selectEntitiesWhereUserId db $ User._userProfileId user
      pure $ Just (user, entities)
    Nothing -> pure Nothing

selectUserByUsername
  :: forall runtime
   . Core.StmDb runtime
  -> User.UserName
  -> IO (Maybe User.UserProfile)
selectUserByUsername db username =
  STM.atomically $ Core.selectUserByUsername db username

selectUserByUsernameResolved
  :: forall runtime
   . Core.StmDb runtime
  -> User.UserName
  -> STM (Maybe (User.UserProfile, [Legal.EntityAndRole]))
selectUserByUsernameResolved db username = do
  let usersTVar = Data._dbUserProfiles db
  users' <- STM.readTVar usersTVar
  case
      find ((== username) . User._userCredsName . User._userProfileCreds) users'
    of
      Just user -> do
        entities <- selectEntitiesWhereUserId db $ User._userProfileId user
        pure $ Just (user, entities)
      Nothing -> pure Nothing

filterUsers :: Runtime -> User.Predicate -> STM [User.UserProfile]
filterUsers runtime predicate = do
  let usersTVar = Data._dbUserProfiles $ _rDb runtime
  users' <- STM.readTVar usersTVar
  pure $ filter (User.applyPredicate predicate) users'

createUser :: User.Signup -> RunM (Either User.UserErr User.UserId)
createUser input = ML.localEnv (<> "Command" <> "CreateUser") $ do
  ML.info $ "Creating user..."
  db   <- asks _rDb
  muid <- liftIO . STM.atomically $ Core.createUser db input
  case muid of
    Right (User.UserId uid) -> ML.info $ "User created: " <> uid
    Left  err               -> ML.info $ "Failed to create user: " <> show err
  pure muid

setUserEmailAddrAsVerified
  :: forall runtime
   . Core.StmDb runtime
  -> User.UserName
  -> STM (Either User.UserErr ())
setUserEmailAddrAsVerified db username = do
  mprofile <- Core.selectUserByUsername db username
  case mprofile of
    Just User.UserProfile {..} -> case _userProfileEmailAddrVerified of
      Nothing -> do
        let replaceOlder users =
              [ if User._userCredsName (User._userProfileCreds u) == username
                  then u { User._userProfileEmailAddrVerified = Just "TODO" }
                  else u
              | u <- users
              ]
        Core.modifyUsers db replaceOlder
        pure $ Right ()
      Just _ -> pure . Left $ User.EmailAddrAlreadyVerified
    Nothing -> pure . Left $ User.UserNotFound $ User.unUserName username

checkCredentials
  :: Core.StmDb Runtime -> User.Credentials -> STM (Maybe User.UserProfile)
checkCredentials db User.Credentials {..} = do
  mprofile <- Core.selectUserByUsername db _userCredsName
  case mprofile of
    Just profile | checkPassword profile _userCredsPassword ->
      pure $ Just profile
    _ -> pure Nothing

-- TODO Use constant-time string comparison.
checkPassword :: User.UserProfile -> User.Password -> Bool
checkPassword profile (User.Password passInput) = storedPass =:= passInput
 where
  User.Password storedPass =
    profile ^. User.userProfileCreds . User.userCredsPassword

userNotFound = Left . User.UserNotFound . mappend "User not found: "

selectEntityBySlug
  :: forall runtime . Core.StmDb runtime -> Text -> STM (Maybe Legal.Entity)
selectEntityBySlug db name = do
  let tvar = Data._dbLegalEntities db
  records <- STM.readTVar tvar
  pure $ find ((== name) . Legal._entitySlug) records

selectEntityBySlugResolved
  :: forall runtime
   . Core.StmDb runtime
  -> Text
  -> STM (Maybe (Legal.Entity, [Legal.ActingUser]))
selectEntityBySlugResolved db name = do
  let tvar = Data._dbLegalEntities db
  records <- STM.readTVar tvar
  case find ((== name) . Legal._entitySlug) records of
    Just entity -> do
      let select (Legal.ActingUserId uid role) = do
            muser <- Core.selectUserById db uid
            pure (muser, role)
      musers <- mapM select $ Legal._entityUsersAndRoles entity
      if any (isNothing . fst) musers
        then pure Nothing -- TODO Error
        else pure . Just . (entity, ) $ map
          (\(Just u, role) -> Legal.ActingUser u role)
          musers
    Nothing -> pure Nothing

-- | Select legal entities where the given user ID is "acting".
selectEntitiesWhereUserId
  :: forall runtime
   . Core.StmDb runtime
  -> User.UserId
  -> STM [Legal.EntityAndRole]
selectEntitiesWhereUserId db uid = do
  let tvar = Data._dbLegalEntities db
  records <- STM.readTVar tvar
  pure $ mapMaybe getEntityAndRole records
 where
  getRole =
    lookup uid
      . map (\(Legal.ActingUserId uid' role) -> (uid', role))
      . Legal._entityUsersAndRoles
  getEntityAndRole e = Legal.EntityAndRole e <$> getRole e

readLegalEntities :: forall runtime . Core.StmDb runtime -> STM [Legal.Entity]
readLegalEntities db = do
  let tvar = Data._dbLegalEntities db
  records <- STM.readTVar tvar
  pure records

withRuntimeAtomically f a = ask >>= \rt -> liftIO . STM.atomically $ f rt a


--------------------------------------------------------------------------------
readForm
  :: forall runtime a
   . (Core.StmDb runtime -> STM.TVar (Map (User.UserName, Text) a))
  -> Core.StmDb runtime
  -> (User.UserProfile, Text)
  -> STM (Either () a)
readForm getTVar db (profile, key) = do
  m <- STM.readTVar $ getTVar db
  let mform = M.lookup (username, key) m
  pure $ maybe (Left ()) Right mform
  where username = User._userCredsName $ User._userProfileCreds profile

readForms
  :: forall runtime a
   . (Core.StmDb runtime -> STM.TVar (Map (User.UserName, Text) a))
  -> Core.StmDb runtime
  -> User.UserProfile
  -> STM (Either () [(Text, a)])
readForms getTVar db profile = do
  m <- STM.readTVar $ getTVar db
  let mform = M.filterWithKey (\(username', _) _ -> username == username') m
  pure $ Right $ map (\((_, key), a) -> (key, a)) $ M.toList mform
  where username = User._userCredsName $ User._userProfileCreds profile

deleteForm
  :: forall runtime a
   . (Core.StmDb runtime -> STM.TVar (Map (User.UserName, Text) a))
  -> Core.StmDb runtime
  -> (User.UserProfile, Text)
  -> STM ()
deleteForm getTVar db (profile, key) =
  let tvar = getTVar db
      f    = M.delete (username, key)
  in  STM.modifyTVar tvar f
  where username = User._userCredsName $ User._userProfileCreds profile


--------------------------------------------------------------------------------
-- TODO Integrity check:
-- All UserIds must resolve: _entityUsersAndRoles.
-- List containing UserIds should not have duplicates: _entityUsersAndRoles.


--------------------------------------------------------------------------------
newtype IOErr = FileDoesntExistErr FilePath
  deriving Show

instance Errs.IsRuntimeErr IOErr where
  errCode FileDoesntExistErr{} = "ERR.FILE_NOT_FOUND"
  httpStatus FileDoesntExistErr{} = HTTP.notFound404
  userMessage = Just . \case
    FileDoesntExistErr fpath -> T.unwords ["File doesn't exist:", T.pack fpath]

-- | A placeholder error type, used until better handling (at the call site) is
-- put in place.
newtype UnspeciedErr = UnspeciedErr Text
  deriving Show

instance Errs.IsRuntimeErr UnspeciedErr where
  errCode UnspeciedErr{} = "ERR.FILE_NOT_FOUND"
  httpStatus UnspeciedErr{} = HTTP.notFound404
  userMessage = Just . \case
    UnspeciedErr msg -> T.unwords ["Error:", msg]
