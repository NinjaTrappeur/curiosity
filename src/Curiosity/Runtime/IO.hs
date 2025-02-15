module Curiosity.Runtime.IO
  (
    -- * managing runtimes: boot, shutdown etc. 
    bootConf
  , bootDbAndLogFile
  , instantiateDb
  , readDb
  , readDbSafe
  , powerdown
  , saveDb
  , saveDbAs
  , readFullStmDbInHask 
  ) where

import qualified Curiosity.Core                as Core
import qualified Data.ByteString.Lazy          as BS
import qualified Commence.Multilogging         as ML
import qualified Commence.Runtime.Errors       as Errs
import qualified Control.Concurrent.STM        as STM
import           Control.Lens
import qualified Curiosity.Data                as Data
import qualified Curiosity.Parse               as Command
import qualified Curiosity.Runtime.Error       as RErr
import           Curiosity.Runtime.Type
import qualified Data.Text                     as T
import qualified Data.Text.Encoding            as TE
import qualified Data.Text.IO                  as T
import           System.Directory               ( doesFileExist )


--------------------------------------------------------------------------------
-- | Boot up a runtime.
bootConf
  :: MonadIO m
  => Command.Conf -- ^ configuration to bootConf with.
  -> Threads
  -> m (Either Errs.RuntimeErr Runtime)
bootConf _rConf _rThreads =
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
bootDbAndLogFile :: MonadIO m => Data.HaskDb -> FilePath -> m Runtime
bootDbAndLogFile db logsPath = do
  let loggingConf = Command.mkLoggingConf logsPath
      _rConf      = Command.defaultConf { Command._confLogging = loggingConf }
  _rDb      <- liftIO . STM.atomically $ Core.instantiateStmDb db
  _rLoggers <- ML.makeDefaultLoggersWithConf loggingConf
  let _rThreads = NoThreads
  pure $ Runtime { .. }

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
  -> m (Either Errs.RuntimeErr Core.StmDb)
instantiateDb Command.Conf {..} = readDbSafe _confDbFile

readDb
  :: forall m
   . MonadIO m
  => Maybe FilePath
  -> m (Either Errs.RuntimeErr Core.StmDb)
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
  useEmpty = Right <$> liftIO (STM.atomically Core.instantiateEmptyStmDb)
  useState = fmap Right . liftIO . STM.atomically . Core.instantiateStmDb

-- | A safer version of readDb: this fails if the file doesn't exist or is
-- empty. This helps in catching early mistake, e.g. from user specifying the
-- wrong file name on the command-line.
readDbSafe
  :: forall m
   . MonadIO m
  => Maybe FilePath
  -> m (Either Errs.RuntimeErr Core.StmDb)
readDbSafe mpath = case mpath of
  Just fpath -> do
    -- We may want to read the file only when the file exists.
    exists <- liftIO $ doesFileExist fpath
    if exists
      then fromFile fpath
      else pure . Left . Errs.knownErr $ RErr.FileDoesntExistErr fpath
  Nothing -> useEmpty
 where
  fromFile fpath = do
    fdata <- liftIO (T.readFile fpath)
    Data.deserialiseDbStrict (TE.encodeUtf8 fdata)
      & either (pure . Left . Errs.knownErr) useState
  useEmpty = Right <$> liftIO (STM.atomically Core.instantiateEmptyStmDb)
  useState = fmap Right . liftIO . STM.atomically . Core.instantiateStmDb

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

-- | Reads all values of the `Db` product type from `STM.STM` to @Hask@.
readFullStmDbInHask
  :: MonadIO m
  => Core.StmDb
  -> m Data.HaskDb
readFullStmDbInHask = liftIO . STM.atomically . Core.readFullStmDbInHask'
