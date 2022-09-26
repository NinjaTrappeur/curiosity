{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DataKinds
           , TypeOperators
#-} -- Language extensions needed for servant.
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TemplateHaskell #-}
{- |
Module: Curiosity.Server
Description: Server root module, split up into public and private sub-modules.

-}
module Curiosity.Server
  ( App
    -- * Top level server types.
  , serverT
  , serve
  , routingLayout
  , run

    -- * Type-aliases for convenience
  , ServerSettings
  ) where

import qualified Commence.JSON.Pretty          as JP
import qualified Commence.Multilogging         as ML
import qualified Commence.Runtime.Errors       as Errs
import qualified Commence.Runtime.Storage      as S
import qualified Commence.Server.Auth          as CAuth
import           Control.Lens
import "exceptions" Control.Monad.Catch         ( MonadMask )
import qualified Curiosity.Data                as Data
import           Curiosity.Data                 ( HaskDb
                                                , readFullStmDbInHask
                                                )
import qualified Curiosity.Data.Business       as Business
import qualified Curiosity.Data.Employment     as Employment
import qualified Curiosity.Data.Legal          as Legal
import qualified Curiosity.Data.SimpleContract as SimpleContract
import qualified Curiosity.Data.User           as User
import qualified Curiosity.Form.Login          as Login
import qualified Curiosity.Form.Signup         as Signup
import qualified Curiosity.Html.Action         as Pages
import qualified Curiosity.Html.Business       as Pages
import qualified Curiosity.Html.Employment     as Pages
import qualified Curiosity.Html.Errors         as Pages
import qualified Curiosity.Html.Homepage       as Pages
import qualified Curiosity.Html.Invoice        as Pages
import qualified Curiosity.Html.LandingPage    as Pages
import qualified Curiosity.Html.Legal          as Pages
import qualified Curiosity.Html.Profile        as Pages
import qualified Curiosity.Html.Run            as Pages
import qualified Curiosity.Html.SimpleContract as Pages
import qualified Curiosity.Interpret           as Inter
import qualified Curiosity.Parse               as Command
import qualified Curiosity.Runtime             as Rt
import qualified Curiosity.Server.Helpers      as H
import           Data.Aeson                     ( FromJSON
                                                , Value
                                                , eitherDecode
                                                )
import qualified Data.ByteString.Lazy          as BS
import           Data.List                      ( (!!) )
import qualified Data.Text                     as T
import qualified Data.Text.Lazy                as LT
import qualified Network.HTTP.Types            as HTTP
import qualified Network.Wai                   as Wai
import qualified Network.Wai.Handler.Warp      as Warp
import           Network.WebSockets.Connection
import           Prelude                 hiding ( Handler )
import           Servant                 hiding ( serve )
import           Servant.API.WebSocket
import qualified Servant.Auth.Server           as SAuth
import qualified Servant.Auth.Server.Internal.Cookie
                                               as SAuth.Cookie
import qualified Servant.HTML.Blaze            as B
import qualified Servant.Server                as Server
import           Smart.Server.Page              ( PageEither )
import qualified Smart.Server.Page             as SS.P
import           System.FilePath                ( (</>) )
import qualified Text.Blaze.Html5              as H
import qualified Text.Blaze.Renderer.Text      as R
                                                ( renderMarkup )
import           Text.Blaze.Renderer.Utf8       ( renderMarkup )
import           WaiAppStatic.Storage.Filesystem
                                                ( defaultWebAppSettings )
import           WaiAppStatic.Storage.Filesystem.Extended
                                                ( hashFileIfExists
                                                , webAppLookup
                                                )
import           WaiAppStatic.Types             ( ss404Handler
                                                , ssLookupFile
                                                )


--------------------------------------------------------------------------------
-- brittany-disable-next-binding
-- | This is the main Servant API definition for Curiosity.
type App = H.UserAuthentication :> Get '[B.HTML] (PageEither
               Pages.LandingPage
               Pages.WelcomePage
             )

             -- Non-authenticated forms, for documentation purpose.

             :<|> "forms" :> "login" :> Get '[B.HTML] Login.Page
             :<|> "forms" :> "signup" :> Get '[B.HTML] Signup.Page
             :<|> "forms" :> "profile" :> Get '[B.HTML] Pages.ProfilePage

             :<|> "forms" :> "new" :> "contract"
                  :> Get '[B.HTML] Pages.CreateContractPage
             :<|> "forms" :> "edit" :> "contract"
                  :> Capture "key" Text
                  :> Get '[B.HTML] Pages.CreateContractPage
             :<|> "forms" :> "edit" :> "contract" :> "add-expense"
                  :> Capture "key" Text
                  :> Get '[B.HTML] Pages.AddExpensePage
             :<|> "forms" :> "edit" :> "contract" :> "edit-expense"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> Get '[B.HTML] Pages.AddExpensePage
             :<|> "forms" :> "edit" :> "contract" :> "remove-expense"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> Get '[B.HTML] Pages.RemoveExpensePage
             :<|> "forms" :> "edit" :> "contract" :> "confirm-contract"
                  :> Capture "key" Text
                  :> Get '[B.HTML] Pages.ConfirmContractPage

             :<|> "forms" :> "new" :> "simple-contract"
                  :> Get '[B.HTML] Pages.CreateSimpleContractPage
             :<|> "forms" :> "edit" :> "simple-contract"
                  :> Capture "key" Text
                  :> Get '[B.HTML] Pages.CreateSimpleContractPage
             :<|> "forms" :> "edit" :> "simple-contract" :> "select-role"
                  :> Capture "key" Text
                  :> Get '[B.HTML] Pages.SelectRolePage
             :<|> "forms" :> "edit" :> "simple-contract" :> "confirm-role"
                  :> Capture "key" Text
                  :> Capture "role" Text
                  :> Get '[B.HTML] Pages.ConfirmRolePage
             :<|> "forms" :> "edit" :> "simple-contract" :> "add-date"
                  :> Capture "key" Text
                  :> Get '[B.HTML] Pages.AddDatePage
             :<|> "forms" :> "edit" :> "simple-contract" :> "edit-date"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> Get '[B.HTML] Pages.AddDatePage
             :<|> "forms" :> "edit" :> "simple-contract" :> "remove-date"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> Get '[B.HTML] Pages.RemoveDatePage
             :<|> "forms" :> "edit" :> "simple-contract" :> "select-vat"
                  :> Capture "key" Text
                  :> Get '[B.HTML] Pages.SelectVATPage
             :<|> "forms" :> "edit" :> "simple-contract" :> "confirm-vat"
                  :> Capture "key" Text
                  :> Capture "rate" Int
                  :> Get '[B.HTML] Pages.ConfirmVATPage
             :<|> "forms" :> "edit" :> "simple-contract" :> "add-expense"
                  :> Capture "key" Text
                  :> Get '[B.HTML] Pages.SimpleContractAddExpensePage
             :<|> "forms" :> "edit" :> "simple-contract" :> "edit-expense"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> Get '[B.HTML] Pages.SimpleContractAddExpensePage
             :<|> "forms" :> "edit" :> "simple-contract" :> "remove-expense"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> Get '[B.HTML] Pages.SimpleContractRemoveExpensePage
             :<|> "forms" :> "edit" :> "simple-contract" :> "confirm-simple-contract"
                  :> Capture "key" Text
                  :> Get '[B.HTML] Pages.ConfirmSimpleContractPage

             :<|> "views" :> "profile"
                  :> Capture "filename" FilePath
                  :> Get '[B.HTML] Pages.ProfileView
             :<|> "views" :> "entity"
                  :> Capture "filename" FilePath
                  :> Get '[B.HTML] Pages.EntityView
             :<|> "views" :> "unit"
                  :> Capture "filename" FilePath
                  :> Get '[B.HTML] Pages.UnitView
             :<|> "views" :> "contract"
                  :> Capture "filename" FilePath
                  :> Get '[B.HTML] Pages.ContractView
             :<|> "views" :> "invoice"
                  :> Capture "filename" FilePath
                  :> Get '[B.HTML] Pages.InvoiceView

             :<|> "messages" :> "signup" :> Get '[B.HTML] Signup.SignupResultPage

             :<|> "run" :> H.UserAuthentication :> Get '[B.HTML] Pages.RunPage
             :<|> "a" :> "run" :> H.UserAuthentication
                  :> ReqBody '[FormUrlEncoded] Data.Command
                  :> Post '[B.HTML] Pages.EchoPage

             :<|> "state" :> Get '[B.HTML] Pages.EchoPage
             :<|> "state.json" :> Get '[JSON] (JP.PrettyJSON '[ 'JP.DropNulls] (HaskDb Rt.Runtime))

             :<|> "echo" :> "login"
                  :> ReqBody '[FormUrlEncoded] User.Login
                  :> Post '[B.HTML] Pages.EchoPage
             :<|> "echo" :> "signup"
                  :> ReqBody '[FormUrlEncoded] User.Signup
                  :> Post '[B.HTML] Pages.EchoPage

             :<|> "echo" :> "new-contract"
                  :> ReqBody '[FormUrlEncoded] Employment.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "new-contract-and-add-expense"
                  :> ReqBody '[FormUrlEncoded] Employment.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "save-contract"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] Employment.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "save-contract-and-add-expense"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] Employment.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "add-expense"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] Employment.AddExpense
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "save-expense"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> ReqBody '[FormUrlEncoded] Employment.AddExpense
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "remove-expense"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "submit-contract"
                  :> ReqBody '[FormUrlEncoded] Employment.SubmitContract
                  :> Post '[B.HTML] Pages.EchoPage

             :<|> "echo" :> "new-simple-contract"
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "new-simple-contract-and-select-role"
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "new-simple-contract-and-add-date"
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "new-simple-contract-and-select-vat"
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "new-simple-contract-and-add-expense"
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "save-simple-contract"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "save-simple-contract-and-select-role"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "save-simple-contract-and-add-date"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "save-simple-contract-and-select-vat"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "save-simple-contract-and-add-expense"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] SimpleContract.CreateContractAll'
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "select-role"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] SimpleContract.SelectRole
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "add-date"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] SimpleContract.AddDate
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "save-date"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> ReqBody '[FormUrlEncoded] SimpleContract.AddDate
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "remove-date"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "select-vat"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] SimpleContract.SelectVAT
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "simple-contract" :> "add-expense"
                  :> Capture "key" Text
                  :> ReqBody '[FormUrlEncoded] SimpleContract.AddExpense
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "simple-contract" :> "save-expense"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> ReqBody '[FormUrlEncoded] SimpleContract.AddExpense
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )
             :<|> "echo" :> "simple-contract" :> "remove-expense"
                  :> Capture "key" Text
                  :> Capture "index" Int
                  :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                              NoContent
                                            )

             :<|> "partials" :> "username-blocklist" :> Get '[B.HTML] H.Html
             :<|> "partials" :> "username-blocklist.json" :> Get '[JSON] [User.UserName]

             :<|> "login" :> Get '[B.HTML] Login.Page
             :<|> "signup" :> Get '[B.HTML] Signup.Page

             :<|> "action" :> "set-email-addr-as-verified"
                  :> Capture "username" User.UserName
                  :> Get '[B.HTML] Pages.SetUserEmailAddrAsVerifiedPage
             :<|> Public
             :<|> Private
             :<|> "data" :> Raw
             :<|> "ubl" :> Capture "schema" Text
                  :> Capture "filename" FilePath :> Get '[JSON] Value
             :<|> "errors" :> "500" :> Get '[B.HTML, JSON] Text
             :<|> "alice+" :> Get '[B.HTML] Pages.ProfileView
             :<|> "entity" :> H.UserAuthentication
                  :> Capture "name" Text
                  :> Get '[B.HTML] Pages.EntityView
             :<|> WebSocketApi
             -- Catchall for user profiles and business units. This also serves
             -- static files (documentation), and a custom 404 when no user or
             -- business unit are found.
             :<|> Capture "namespace" Text :> Raw

-- brittany-disable-next-binding
type NamespaceAPI = Get '[B.HTML] (PageEither Pages.PublicProfileView Pages.UnitView)


-- | This is the main Servant server definition, corresponding to @App@.
serverT
  :: forall m
   . ServerC m
  => (forall x . m x -> Handler x) -- ^ Natural transformation to transform an
  -> Server.Context ServerSettings
  -> Command.ServerConf
  -> SAuth.JWTSettings
  -> FilePath
  -> FilePath
  -> ServerT App m
serverT natTrans ctx conf jwtS root dataDir =
  showHomePage
    :<|> documentLoginPage
    :<|> documentSignupPage
    :<|> documentEditProfilePage dataDir

    :<|> documentCreateContractPage dataDir
    :<|> documentEditContractPage dataDir
    :<|> documentAddExpensePage dataDir
    :<|> documentEditExpensePage dataDir
    :<|> documentRemoveExpensePage dataDir
    :<|> documentConfirmContractPage dataDir

    :<|> documentCreateSimpleContractPage dataDir
    :<|> documentEditSimpleContractPage dataDir
    :<|> documentSelectRolePage dataDir
    :<|> documentConfirmRolePage dataDir
    :<|> documentAddDatePage dataDir
    :<|> documentEditDatePage dataDir
    :<|> documentRemoveDatePage dataDir
    :<|> documentSelectVATPage dataDir
    :<|> documentConfirmVATPage dataDir
    :<|> documentSimpleContractAddExpensePage dataDir
    :<|> documentSimpleContractEditExpensePage dataDir
    :<|> documentSimpleContractRemoveExpensePage dataDir
    :<|> documentConfirmSimpleContractPage dataDir

    :<|> documentProfilePage dataDir
    :<|> documentEntityPage dataDir
    :<|> documentUnitPage dataDir
    :<|> documentContractPage dataDir
    :<|> documentInvoicePage dataDir
    :<|> messageSignupSuccess

    :<|> showRun
    :<|> handleRun
    :<|> showState
    :<|> showStateAsJson

    :<|> echoLogin
    :<|> echoSignup

    :<|> echoNewContract dataDir
    :<|> echoNewContractAndAddExpense dataDir
    :<|> echoSaveContract dataDir
    :<|> echoSaveContractAndAddExpense dataDir
    :<|> echoAddExpense dataDir
    :<|> echoSaveExpense dataDir
    :<|> echoRemoveExpense dataDir
    :<|> echoSubmitContract dataDir

    :<|> echoNewSimpleContract dataDir
    :<|> echoNewSimpleContractAndSelectRole dataDir
    :<|> echoNewSimpleContractAndAddDate dataDir
    :<|> echoNewSimpleContractAndSelectVAT dataDir
    :<|> echoNewSimpleContractAndAddExpense dataDir
    :<|> echoSaveSimpleContract dataDir
    :<|> echoSaveSimpleContractAndSelectRole dataDir
    :<|> echoSaveSimpleContractAndAddDate dataDir
    :<|> echoSaveSimpleContractAndSelectVAT dataDir
    :<|> echoSaveSimpleContractAndAddExpense dataDir
    :<|> echoSelectRole dataDir
    :<|> echoAddDate dataDir
    :<|> echoSaveDate dataDir
    :<|> echoRemoveDate dataDir
    :<|> echoSelectVAT dataDir
    :<|> echoSimpleContractAddExpense dataDir
    :<|> echoSimpleContractSaveExpense dataDir
    :<|> echoSimpleContractRemoveExpense dataDir

    :<|> partialUsernameBlocklist
    :<|> partialUsernameBlocklistAsJson
    :<|> showLoginPage
    :<|> showSignupPage
    :<|> showSetUserEmailAddrAsVerifiedPage
    :<|> publicT conf jwtS
    :<|> privateT conf
    :<|> serveData dataDir
    :<|> serveUBL dataDir
    :<|> serveErrors
    :<|> serveNamespaceDocumentation "alice"
    :<|> serveEntity
    :<|> websocket
    :<|> serveNamespaceOrStatic natTrans ctx jwtS conf root


--------------------------------------------------------------------------------
-- | Minimal set of constraints needed on some monad @m@ to be satisfied to be
-- able to run a server.
type ServerC m
  = ( MonadMask m
    , ML.MonadAppNameLogMulti m
    , S.DBStorage m STM User.UserProfile
    , S.DBTransaction m STM
    , MonadReader Rt.Runtime m
    , MonadIO m
    , Show (S.DBError m STM User.UserProfile)
    , S.Db m STM User.UserProfile ~ Data.StmDb Rt.Runtime
    )


--------------------------------------------------------------------------------
type ServerSettings
  = '[SAuth.CookieSettings , SAuth.JWTSettings , ErrorFormatters]

-- | This is the main function of this module. It runs a Warp server, serving
-- our @App@ API definition.
run
  :: forall m
   . MonadIO m
  => Command.ServerConf
  -> Rt.Runtime -- ^ Runtime to use for running the server.
  -> m ()
run conf@Command.ServerConf {..} runtime = liftIO $ do
  jwk <- SAuth.generateKey
  let jwtSettings = _serverMkJwtSettings jwk
  Warp.run _serverPort $ waiApp jwtSettings
 where
  waiApp jwtS = serve @Rt.AppM (Rt.appMHandlerNatTrans runtime)
                               conf
                               (ctx jwtS)
                               jwtS
                               _serverStaticDir
                               _serverDataDir
  ctx jwtS =
    _serverCookie
      Server.:. jwtS
      Server.:. errorFormatters
      Server.:. Server.EmptyContext

-- | Turn our @serverT@ definition into a Wai application, suitable for
-- Warp.run.
serve
  :: forall m
   . ServerC m
  => (forall x . m x -> Handler x) -- ^ Natural transformation to transform an
                                   -- arbitrary @m@ to a Servant @Handler@
  -> Command.ServerConf
  -> Server.Context ServerSettings
  -> SAuth.JWTSettings
  -> FilePath
  -> FilePath
  -> Wai.Application
serve handlerNatTrans conf ctx jwtS root dataDir =
  Servant.serveWithContext appProxy ctx
    $ hoistServerWithContext appProxy settingsProxy handlerNatTrans
    $ serverT handlerNatTrans ctx conf jwtS root dataDir

appProxy = Proxy @App
settingsProxy = Proxy @ServerSettings

routingLayout :: forall m . MonadIO m => m Text
routingLayout = do
  let Command.ServerConf {..} = Command.defaultServerConf
  jwk <- liftIO SAuth.generateKey
  let jwtSettings = _serverMkJwtSettings jwk
  let ctx =
        _serverCookie
          Server.:. jwtSettings
          Server.:. errorFormatters
          Server.:. Server.EmptyContext
  pure $ layoutWithContext (Proxy @App) ctx


--------------------------------------------------------------------------------
-- | Show the landing page when the user is not logged in, or the welcome page
-- when the user is logged in.
showHomePage
  :: ServerC m
  => SAuth.AuthResult User.UserId
  -> m (PageEither Pages.LandingPage Pages.WelcomePage)
     -- We don't use SS.P.Public Void, nor SS.P.Public 'Authd UserProfile
     -- to not have the automatic heading.
showHomePage authResult = withMaybeUser
  authResult
  (\_ -> pure $ SS.P.PageL Pages.LandingPage)
  (\profile -> do
    Rt.Runtime {..} <- ask
    b <- liftIO . atomically $ Rt.canPerform 'User.SetUserEmailAddrAsVerified
                                             _rDb
                                             profile
    profiles <- if b
      then
        Just
          <$> Rt.withRuntimeAtomically Rt.filterUsers
                                       User.PredicateEmailAddrToVerify
      else pure Nothing
    pure . SS.P.PageR $ Pages.WelcomePage profile profiles
  )


--------------------------------------------------------------------------------
showSignupPage :: ServerC m => m Signup.Page
showSignupPage = pure $ Signup.Page "/a/signup"

documentSignupPage :: ServerC m => m Signup.Page
documentSignupPage = pure $ Signup.Page "/echo/signup"

messageSignupSuccess :: ServerC m => m Signup.SignupResultPage
messageSignupSuccess = pure Signup.SignupSuccess

echoSignup :: ServerC m => User.Signup -> m Pages.EchoPage
echoSignup input = pure $ Pages.EchoPage $ show input


--------------------------------------------------------------------------------
showSetUserEmailAddrAsVerifiedPage
  :: ServerC m => User.UserName -> m Pages.SetUserEmailAddrAsVerifiedPage
showSetUserEmailAddrAsVerifiedPage username =
  withUserFromUsername username (pure . Pages.SetUserEmailAddrAsVerifiedPage)


--------------------------------------------------------------------------------
partialUsernameBlocklist :: ServerC m => m H.Html
partialUsernameBlocklist =
  pure . H.ul $ mapM_ (H.li . H.code . H.toHtml) User.usernameBlocklist

partialUsernameBlocklistAsJson :: ServerC m => m [User.UserName]
partialUsernameBlocklistAsJson = pure User.usernameBlocklist

--------------------------------------------------------------------------------
showLoginPage :: ServerC m => m Login.Page
showLoginPage = pure $ Login.Page "/a/login"

documentLoginPage :: ServerC m => m Login.Page
documentLoginPage = pure $ Login.Page "/echo/login"

echoLogin :: ServerC m => User.Login -> m Pages.EchoPage
echoLogin = pure . Pages.EchoPage . show


--------------------------------------------------------------------------------
-- brittany-disable-next-binding
-- | A publicly available login page.
type Public =    "a" :> "signup"
                 :> ReqBody '[FormUrlEncoded] User.Signup
                 :> Post '[B.HTML] Signup.SignupResultPage
            :<|> "a" :> "login"
                 :> ReqBody '[FormUrlEncoded] User.Login
                 :> Verb 'POST 303 '[JSON] ( Headers CAuth.PostAuthHeaders
                                              NoContent
                                            )

publicT
  :: forall m
   . ServerC m
  => Command.ServerConf
  -> SAuth.JWTSettings
  -> ServerT Public m
publicT conf jwtS = handleSignup :<|> handleLogin conf jwtS

handleSignup
  :: forall m
   . (ServerC m, Show (S.DBError m STM User.UserProfile))
  => User.Signup
  -> m Signup.SignupResultPage
handleSignup input@User.Signup {..} =
  ML.localEnv (<> "HTTP" <> "Signup")
    $   do
          ML.info $ "Signing up new user: " <> show username <> "..."
          db <- asks Rt._rDb
          S.liftTxn @m @STM
            $ S.dbUpdate @m db (User.UserCreateGeneratingUserId input)
          -- Rt.withRuntimeAtomically Rt.createUser input
    >>= \case
          Right uid -> do
            ML.info
              $  "User created: "
              <> show uid
              <> ". Sending success result."
            pure Signup.SignupSuccess
          Left err -> do
            ML.info
              $  "Failed to create a user. Sending failure result: "
              <> show err
            Errs.throwError' err

handleLogin
  :: forall m
   . ServerC m
  => Command.ServerConf
  -> SAuth.JWTSettings
  -> User.Login
  -> m (Headers CAuth.PostAuthHeaders NoContent)
handleLogin conf jwtSettings input =
  ML.localEnv (<> "HTTP" <> "Login")
    $   do
          ML.info
            $  "Logging in user: "
            <> show (User._loginUsername input)
            <> "..."
          let credentials = User.Credentials (User._loginUsername input)
                                             (User._loginPassword input)
          db <- asks Rt._rDb
          S.liftTxn @m @STM (Rt.checkCredentials db credentials)
    >>= \case
          Right (Just u) -> do
            ML.info "Found user, applying authentication cookies..."
            -- TODO I think jwtSettings could be retrieved with
            -- Servant.Server.getContetEntry. This would avoid threading
            -- jwtSettings evereywhere.
            mApplyCookies <- liftIO $ SAuth.acceptLogin
              (Command._serverCookie conf)
              jwtSettings
              (u ^. User.userProfileId)
            case mApplyCookies of
              Nothing -> do
                -- From a quick look at Servant, it seems the error would be a
                -- JSON-encoding failure of the generated JWT.
                let err = ServerErr "Couldn't apply cookies."
                ML.error
                  $  "Applying cookies failed. Sending failure result: "
                  <> show err
                Errs.throwError' err
              Just applyCookies -> do
                ML.info "Cookies applied. Sending success result."
                pure . addHeader @"Location" "/" $ applyCookies NoContent
          Right Nothing -> reportErr User.IncorrectUsernameOrPassword
          Left  err     -> reportErr err
 where
  reportErr err = do
    ML.info
      $  "Incorrect username or password. Sending failure result: "
      <> show err
    Errs.throwError' err


--------------------------------------------------------------------------------
-- brittany-disable-next-binding
-- | The private API with authentication.
type Private = H.UserAuthentication :> (
                   "settings" :> "profile"
                   :> Get '[B.HTML] Pages.ProfileView
             :<|>  "settings" :> "profile.json"
                   :> Get '[JSON] User.UserProfile
             :<|>  "settings" :> "profile" :> "edit"
                   :> Get '[B.HTML] Pages.ProfilePage

             :<|> "new" :> "entity" :> Get '[B.HTML] Pages.CreateEntityPage
             :<|> "new" :> "unit" :> Get '[B.HTML] Pages.CreateUnitPage
             :<|> "new" :> "contract" :> Get '[B.HTML] Pages.CreateContractPage
             :<|> "new" :> "invoice" :> Get '[B.HTML] Pages.CreateInvoicePage

             :<|>  "a" :>"set-user-profile"
                   :> ReqBody '[FormUrlEncoded] User.Update
                   :> Verb 'POST 303 '[JSON] ( Headers '[ Header "Location" Text ]
                                               NoContent
                                             )
             :<|> "a" :> "logout" :> Verb 'GET 303 '[JSON] ( Headers CAuth.PostLogoutHeaders
                                                             NoContent
                                                            )
             :<|> "a" :> "set-email-addr-as-verified"
                   :> ReqBody '[FormUrlEncoded] User.SetUserEmailAddrAsVerified
                   :> Post '[B.HTML] Pages.ActionResult
  )

privateT :: forall m . ServerC m => Command.ServerConf -> ServerT Private m
privateT conf authResult =
  let withUser'
        :: forall m' a . ServerC m' => (User.UserProfile -> m' a) -> m' a
      withUser' = withUser authResult
  in  (withUser' showProfilePage)
        :<|> (withUser' showProfileAsJson)
        :<|> (withUser' showEditProfilePage)
        :<|> (withUser' showCreateEntityPage)
        :<|> (withUser' showCreateUnitPage)
        :<|> (withUser' showCreateContractPage)
        :<|> (withUser' showCreateInvoicePage)
        :<|> (withUser' . handleUserProfileUpdate)
        :<|> (withUser' $ const (handleLogout conf))
        :<|> (withUser' . handleSetUserEmailAddrAsVerified)

--------------------------------------------------------------------------------
-- | Handle a user's logout.
handleLogout
  :: forall m
   . ServerC m
  => Command.ServerConf
  -> m (Headers CAuth.PostLogoutHeaders NoContent)
handleLogout conf = pure . addHeader @"Location" "/" $ SAuth.clearSession
  (Command._serverCookie conf)
  NoContent

showProfilePage profile =
  pure $ Pages.ProfileView profile (Just "/settings/profile/edit")

showProfileAsJson
  :: forall m . ServerC m => User.UserProfile -> m User.UserProfile
showProfileAsJson = pure

showEditProfilePage profile =
  pure $ Pages.ProfilePage profile "/a/set-user-profile"

showCreateEntityPage
  :: ServerC m => User.UserProfile -> m Pages.CreateEntityPage
showCreateEntityPage profile =
  pure $ Pages.CreateEntityPage profile "/a/new-entity"

showCreateUnitPage :: ServerC m => User.UserProfile -> m Pages.CreateUnitPage
showCreateUnitPage profile = pure $ Pages.CreateUnitPage profile "/a/new-unit"

showCreateContractPage
  :: ServerC m => User.UserProfile -> m Pages.CreateContractPage
showCreateContractPage profile = pure $ Pages.CreateContractPage
  profile
  Nothing
  Employment.emptyCreateContractAll
  "/a/new-contract"
  "/a/new-contract-and-add-expense"

showCreateInvoicePage
  :: ServerC m => User.UserProfile -> m Pages.CreateInvoicePage
showCreateInvoicePage profile =
  pure $ Pages.CreateInvoicePage profile "/a/new-invoice"


--------------------------------------------------------------------------------
handleUserProfileUpdate
  :: forall m
   . ServerC m
  => User.Update
  -> User.UserProfile
  -> m (Headers '[Header "Location" Text] NoContent)
handleUserProfileUpdate update profile = do
  db   <- asks Rt._rDb
  eIds <- S.liftTxn
    (S.dbUpdate @m @STM db (User.UserUpdate (S.dbId profile) update))

  case eIds of
    Right (Right [_]) ->
      pure $ addHeader @"Location" ("/settings/profile") NoContent
    _ -> Errs.throwError' $ Rt.UnspeciedErr "Cannot update the user."

handleSetUserEmailAddrAsVerified
  :: forall m
   . ServerC m
  => User.SetUserEmailAddrAsVerified
  -> User.UserProfile
  -> m Pages.ActionResult
handleSetUserEmailAddrAsVerified (User.SetUserEmailAddrAsVerified username) profile
  = do
    db     <- asks Rt._rDb
    output <- liftIO . atomically $ Rt.setUserEmailAddrAsVerifiedFull
      db
      (profile, username)
    pure $ Pages.ActionResult "Set email address as verified" $ case output of
      Right ()  -> "Success"
      Left  err -> "Failure: " <> show err

-- $ documentationPages
--
-- The \`document` -prefixed functions display the same page as the \`show`
-- -prefixed one.

documentEditProfilePage :: ServerC m => FilePath -> m Pages.ProfilePage
documentEditProfilePage dataDir = do
  profile <- readJson $ dataDir </> "alice.json"
  pure $ Pages.ProfilePage profile "/echo/profile"

documentCreateContractPage
  :: ServerC m => FilePath -> m Pages.CreateContractPage
documentCreateContractPage dataDir = do
  profile <- readJson $ dataDir </> "alice.json"
  let contractAll = Employment.emptyCreateContractAll
  pure $ Pages.CreateContractPage profile
                                  Nothing
                                  contractAll
                                  "/echo/new-contract"
                                  "/echo/new-contract-and-add-expense"

-- | Same as documentCreateContractPage, but use an existing form.
documentEditContractPage
  :: ServerC m => FilePath -> Text -> m Pages.CreateContractPage
documentEditContractPage dataDir key = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateContractForm db (profile, key)
  case output of
    Right contractAll -> pure $ Pages.CreateContractPage
      profile
      (Just key)
      contractAll
      (H.toValue $ "/echo/save-contract/" <> key)
      (H.toValue $ "/echo/save-contract-and-add-expense/" <> key)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentAddExpensePage
  :: ServerC m => FilePath -> Text -> m Pages.AddExpensePage
documentAddExpensePage dataDir key = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateContractForm db (profile, key)
  case output of
    Right _ -> pure $ Pages.AddExpensePage
      profile
      key
      Nothing
      Employment.emptyAddExpense
      (H.toValue $ "/echo/add-expense/" <> key)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

-- | Same as documentAddExpensePage, but use an existing form.
documentEditExpensePage
  :: ServerC m => FilePath -> Text -> Int -> m Pages.AddExpensePage
documentEditExpensePage dataDir key index = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateContractForm db (profile, key)
  case output of
    Right (Employment.CreateContractAll _ _ _ _ _ expenses) ->
      if index > length expenses - 1
        then Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.
        else pure $ Pages.AddExpensePage
          profile
          key
          (Just index)
          (expenses !! index)
          (H.toValue $ "/echo/save-expense/" <> key <> "/" <> show index)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentRemoveExpensePage
  :: ServerC m => FilePath -> Text -> Int -> m Pages.RemoveExpensePage
documentRemoveExpensePage dataDir key index = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateContractForm db (profile, key)
  case output of
    Right (Employment.CreateContractAll _ _ _ _ _ expenses) ->
      if index > length expenses - 1
        then Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.
        else pure $ Pages.RemoveExpensePage
          profile
          key
          index
          (expenses !! index)
          (H.toValue $ "/echo/remove-expense/" <> key <> "/" <> show index)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

-- | Create a form, generating a new key. This is normally used with a
-- \"Location" header.
echoNewContract'
  :: ServerC m
  => FilePath
  -> Employment.CreateContractAll'
  -> m Text
echoNewContract' dataDir contract = do
  profile <- readJson $ dataDir </> "alice.json"
  db <- asks Rt._rDb
  key <- liftIO . atomically $ Rt.newCreateContractForm db (profile, contract)
  pure key

-- | Create a form, generating a new key.
echoNewContract
  :: ServerC m
  => FilePath
  -> Employment.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoNewContract dataDir contract = do
  key <- echoNewContract' dataDir contract
  pure $ addHeader @"Location" ("/forms/edit/contract/confirm-contract/" <> key) NoContent

-- | Create a form, then move to the add expense part.
echoNewContractAndAddExpense
  :: ServerC m
  => FilePath
  -> Employment.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoNewContractAndAddExpense dataDir contract = do
  key <- echoNewContract' dataDir contract
  pure $ addHeader @"Location" ("/forms/edit/contract/add-expense/" <> key) NoContent

-- | Save a form, re-using a key. This is normally used with a \"Location"
-- header.
echoSaveContract'
  :: ServerC m
  => FilePath
  -> Text
  -> Employment.CreateContractAll'
  -> m ()
echoSaveContract' dataDir key contract = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  todo    <- liftIO . atomically $ Rt.writeCreateContractForm
    db
    (profile, key, contract)
  pure ()

-- | Save a form, re-using a key.
echoSaveContract
  :: ServerC m
  => FilePath
  -> Text
  -> Employment.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoSaveContract dataDir key contract = do
  echoSaveContract' dataDir key contract
  pure $ addHeader @"Location" ("/forms/edit/contract/confirm-contract/" <> key) NoContent

-- | Save a form, re-using a key, then move to the add expense part.
echoSaveContractAndAddExpense
  :: ServerC m
  => FilePath
  -> Text
  -> Employment.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoSaveContractAndAddExpense dataDir key contract = do
  echoSaveContract' dataDir key contract
  pure $ addHeader @"Location" ("/forms/edit/contract/add-expense/" <> key) NoContent

echoAddExpense
  :: ServerC m
  => FilePath
  -> Text
  -> Employment.AddExpense
  -> m (Headers '[Header "Location" Text] NoContent)
echoAddExpense dataDir key expense = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  liftIO . atomically $ Rt.addExpenseToContractForm db (profile, key, expense)
  pure $ addHeader @"Location"
    ("/forms/edit/contract/" <> key <> "#panel-expenses")
    NoContent

-- | Save an expense, re-using a key and an index.
echoSaveExpense
  :: ServerC m
  => FilePath
  -> Text
  -> Int
  -> Employment.AddExpense
  -> m (Headers '[Header "Location" Text] NoContent)
echoSaveExpense dataDir key index expense = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  todo    <- liftIO . atomically $ Rt.writeExpenseToContractForm
    db
    (profile, key, index, expense)
  pure $ addHeader @"Location"
    ("/forms/edit/contract/" <> key <> "#panel-expenses")
    NoContent

echoRemoveExpense
  :: ServerC m
  => FilePath
  -> Text
  -> Int
  -> m (Headers '[Header "Location" Text] NoContent)
echoRemoveExpense dataDir key index = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  todo    <- liftIO . atomically $ Rt.removeExpenseFromContractForm
    db
    (profile, key, index)
  pure $ addHeader @"Location"
    ("/forms/edit/contract/" <> key <> "#panel-expenses")
    NoContent

documentConfirmContractPage
  :: ServerC m => FilePath -> Text -> m Pages.ConfirmContractPage
documentConfirmContractPage dataDir key = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateContractForm db (profile, key)
  case output of
    Right contractAll -> pure $ Pages.ConfirmContractPage
      profile
      key
      contractAll
      "/echo/submit-contract"
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

echoSubmitContract
  :: ServerC m => FilePath -> Employment.SubmitContract -> m Pages.EchoPage
echoSubmitContract dataDir (Employment.SubmitContract key) = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateContractForm db (profile, key)
  case output of
    Right contract -> pure . Pages.EchoPage $ show
      (contract, Employment.validateCreateContract profile contract)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.


--------------------------------------------------------------------------------
-- | Create a form, generating a new key. This is normally used with a
-- \"Location" header.
echoNewSimpleContract'
  :: ServerC m
  => FilePath
  -> SimpleContract.CreateContractAll'
  -> m Text
echoNewSimpleContract' dataDir contract = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  key     <- liftIO . atomically $ Rt.newCreateSimpleContractForm
    db
    (profile, contract)
  pure key

-- | Create a form, then move to the confirmation page.
echoNewSimpleContract
  :: ServerC m
  => FilePath
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoNewSimpleContract dataDir contract = do
  key <- echoNewSimpleContract' dataDir contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/confirm-simple-contract/" <> key)
                               NoContent

-- | Create a form, then move to the select role part.
echoNewSimpleContractAndSelectRole
  :: ServerC m
  => FilePath
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoNewSimpleContractAndSelectRole dataDir contract = do
  key <- echoNewSimpleContract' dataDir contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/select-role/" <> key) NoContent

-- | Create a form, then move to the add date part.
echoNewSimpleContractAndAddDate
  :: ServerC m
  => FilePath
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoNewSimpleContractAndAddDate dataDir contract = do
  key <- echoNewSimpleContract' dataDir contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/add-date/" <> key) NoContent

-- | Create a form, then move to the select VAT part.
echoNewSimpleContractAndSelectVAT
  :: ServerC m
  => FilePath
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoNewSimpleContractAndSelectVAT dataDir contract = do
  key <- echoNewSimpleContract' dataDir contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/select-vat/" <> key) NoContent

-- | Create a form, then move to the add expense part.
echoNewSimpleContractAndAddExpense
  :: ServerC m
  => FilePath
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoNewSimpleContractAndAddExpense dataDir contract = do
  key <- echoNewSimpleContract' dataDir contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/add-expense/" <> key) NoContent

-- | Save a form, re-using a key. This is normally used with a \"Location"
-- header.
echoSaveSimpleContract'
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.CreateContractAll'
  -> m ()
echoSaveSimpleContract' dataDir key contract = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  todo    <- liftIO . atomically $ Rt.writeCreateSimpleContractForm
    db
    (profile, key, contract)
  pure ()

-- | Save a form, re-using a key.
echoSaveSimpleContract
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoSaveSimpleContract dataDir key contract = do
  echoSaveSimpleContract' dataDir key contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/confirm-simple-contract/" <> key) NoContent

-- | Save a form, re-using a key, then move to the select role part.
echoSaveSimpleContractAndSelectRole
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoSaveSimpleContractAndSelectRole dataDir key contract = do
  echoSaveSimpleContract' dataDir key contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/select-role/" <> key) NoContent

-- | Save a form, re-using a key, then move to the select date part.
echoSaveSimpleContractAndAddDate
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoSaveSimpleContractAndAddDate dataDir key contract = do
  echoSaveSimpleContract' dataDir key contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/add-date/" <> key) NoContent

-- | Save a form, re-using a key, then move to the select VAT part.
echoSaveSimpleContractAndSelectVAT
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoSaveSimpleContractAndSelectVAT dataDir key contract = do
  echoSaveSimpleContract' dataDir key contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/select-vat/" <> key) NoContent

-- | Save a form, re-using a key, then move to the add expense part.
echoSaveSimpleContractAndAddExpense
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.CreateContractAll'
  -> m (Headers '[Header "Location" Text] NoContent)
echoSaveSimpleContractAndAddExpense dataDir key contract = do
  echoSaveSimpleContract' dataDir key contract
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/add-expense/" <> key) NoContent

echoSelectRole
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.SelectRole
  -> m (Headers '[Header "Location" Text] NoContent)
echoSelectRole dataDir key role = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  liftIO . atomically $ Rt.addRoleToSimpleContractForm db (profile, key, role)
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/" <> key) NoContent

echoAddDate
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.AddDate
  -> m (Headers '[Header "Location" Text] NoContent)
echoAddDate dataDir key date = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  liftIO . atomically $ Rt.addDateToSimpleContractForm db (profile, key, date)
  pure $ addHeader @"Location"
    ("/forms/edit/simple-contract/" <> key <> "#panel-dates")
    NoContent

-- | Save a date, re-using a key and an index.
echoSaveDate
  :: ServerC m
  => FilePath
  -> Text
  -> Int
  -> SimpleContract.AddDate
  -> m (Headers '[Header "Location" Text] NoContent)
echoSaveDate dataDir key index date = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  todo    <- liftIO . atomically $ Rt.writeDateToSimpleContractForm
    db
    (profile, key, index, date)
  pure $ addHeader @"Location"
    ("/forms/edit/simple-contract/" <> key <> "#panel-dates")
    NoContent

echoRemoveDate
  :: ServerC m
  => FilePath
  -> Text
  -> Int
  -> m (Headers '[Header "Location" Text] NoContent)
echoRemoveDate dataDir key index = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  todo    <- liftIO . atomically $ Rt.removeDateFromSimpleContractForm
    db
    (profile, key, index)
  pure $ addHeader @"Location"
    ("/forms/edit/simple-contract/" <> key <> "#panel-dates")
    NoContent

echoSelectVAT
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.SelectVAT
  -> m (Headers '[Header "Location" Text] NoContent)
echoSelectVAT dataDir key rate = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  liftIO . atomically $ Rt.addVATToSimpleContractForm db (profile, key, rate)
  pure $ addHeader @"Location" ("/forms/edit/simple-contract/" <> key) NoContent

echoSimpleContractAddExpense
  :: ServerC m
  => FilePath
  -> Text
  -> SimpleContract.AddExpense
  -> m (Headers '[Header "Location" Text] NoContent)
echoSimpleContractAddExpense dataDir key expense = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  liftIO . atomically $ Rt.addExpenseToSimpleContractForm db (profile, key, expense)
  pure $ addHeader @"Location"
    ("/forms/edit/simple-contract/" <> key <> "#panel-expenses")
    NoContent

-- | Save an expense, re-using a key and an index.
echoSimpleContractSaveExpense
  :: ServerC m
  => FilePath
  -> Text
  -> Int
  -> SimpleContract.AddExpense
  -> m (Headers '[Header "Location" Text] NoContent)
echoSimpleContractSaveExpense dataDir key index expense = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  todo    <- liftIO . atomically $ Rt.writeExpenseToSimpleContractForm
    db
    (profile, key, index, expense)
  pure $ addHeader @"Location"
    ("/forms/edit/simple-contract/" <> key <> "#panel-expenses")
    NoContent

echoSimpleContractRemoveExpense
  :: ServerC m
  => FilePath
  -> Text
  -> Int
  -> m (Headers '[Header "Location" Text] NoContent)
echoSimpleContractRemoveExpense dataDir key index = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  todo    <- liftIO . atomically $ Rt.removeExpenseFromSimpleContractForm
    db
    (profile, key, index)
  pure $ addHeader @"Location"
    ("/forms/edit/simple-contract/" <> key <> "#panel-expenses")
    NoContent


--------------------------------------------------------------------------------
documentCreateSimpleContractPage
  :: ServerC m => FilePath -> m Pages.CreateSimpleContractPage
documentCreateSimpleContractPage dataDir = do
  profile <- readJson $ dataDir </> "alice.json"
  let contractAll = SimpleContract.emptyCreateContractAll
      role        = SimpleContract._createContractRole
        $ SimpleContract._createContractType contractAll
  -- This acts like a validation pass. Some higher level function to do that should
  -- exists. TODO
  case Pages.lookupRoleLabel role of
    Just roleLabel -> pure $ Pages.CreateSimpleContractPage
      profile
      Nothing
      contractAll
      roleLabel
      "/echo/new-simple-contract"
      "/echo/new-simple-contract-and-select-role"
      "/echo/new-simple-contract-and-add-date"
      "#" -- Should not appear
      "#" -- Should not appear
      "/echo/new-simple-contract-and-select-vat"
      "/echo/new-simple-contract-and-add-expense"
      "#" -- Should not appear
      "#" -- Should not appear
    Nothing -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack role -- TODO Specific error.

documentEditSimpleContractPage
  :: ServerC m => FilePath -> Text -> m Pages.CreateSimpleContractPage
documentEditSimpleContractPage dataDir key = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm
    db
    (profile, key)
  case output of
    Right contractAll -> do
      let role = SimpleContract._createContractRole
            $ SimpleContract._createContractType contractAll
      case Pages.lookupRoleLabel role of
        Just roleLabel -> pure $ Pages.CreateSimpleContractPage
          profile
          (Just key)
          contractAll
          roleLabel
          (H.toValue $ "/echo/save-simple-contract/" <> key)
          (H.toValue $ "/echo/save-simple-contract-and-select-role/" <> key)
          (H.toValue $ "/echo/save-simple-contract-and-add-date/" <> key)
          "/forms/edit/simple-contract/edit-date/"
          "/forms/edit/simple-contract/remove-date/"
          (H.toValue $ "/echo/save-simple-contract-and-select-vat/" <> key)
          (H.toValue $ "/echo/save-simple-contract-and-add-expense/" <> key)
          "/forms/edit/simple-contract/edit-expense/"
          "/forms/edit/simple-contract/remove-expense/"
        Nothing -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack role -- TODO Specific error.
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentSelectRolePage
  :: ServerC m => FilePath -> Text -> m Pages.SelectRolePage
documentSelectRolePage dataDir key = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm
    db
    (profile, key)
  case output of
    Right _ -> pure $ Pages.SelectRolePage profile key "/forms/edit/simple-contract/confirm-role/"
    Left  _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentConfirmRolePage
  :: ServerC m => FilePath -> Text -> Text -> m Pages.ConfirmRolePage
documentConfirmRolePage dataDir key role = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm
    db
    (profile, key)
  case output of
    Right _ -> do
      case Pages.lookupRoleLabel role of
        Just roleLabel -> pure $ Pages.ConfirmRolePage
          profile
          key
          role
          roleLabel
          (H.toValue $ "/forms/edit/simple-contract/" <> key <> "#panel-type")
          (H.toValue $ "/echo/select-role/" <> key)
        Nothing -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack role -- TODO Specific error.
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentAddDatePage
  :: ServerC m => FilePath -> Text -> m Pages.AddDatePage
documentAddDatePage dataDir key = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm db (profile, key)
  case output of
    Right _ -> pure $ Pages.AddDatePage
      profile
      key
      Nothing
      SimpleContract.emptyAddDate
      (H.toValue $ "/forms/edit/simple-contract/" <> key <> "#panel-dates")
      (H.toValue $ "/echo/add-date/" <> key)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

-- | Same as documentAddDatePage, but use an existing form.
documentEditDatePage
  :: ServerC m => FilePath -> Text -> Int -> m Pages.AddDatePage
documentEditDatePage dataDir key index = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm db (profile, key)
  case output of
    Right (SimpleContract.CreateContractAll _ _ _ _ dates _) ->
      if index > length dates - 1
        then Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.
        else pure $ Pages.AddDatePage
          profile
          key
          (Just index)
          (dates !! index)
          (H.toValue $ "/forms/edit/simple-contract/" <> key <> "#panel-dates")
          (H.toValue $ "/echo/save-date/" <> key <> "/" <> show index)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentRemoveDatePage
  :: ServerC m => FilePath -> Text -> Int -> m Pages.RemoveDatePage
documentRemoveDatePage dataDir key index = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm db (profile, key)
  case output of
    Right (SimpleContract.CreateContractAll _ _ _ _ dates _) ->
      if index > length dates - 1
        then Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.
        else pure $ Pages.RemoveDatePage
          profile
          key
          index
          (dates !! index)
          (H.toValue $ "/echo/remove-date/" <> key <> "/" <> show index)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentSelectVATPage
  :: ServerC m => FilePath -> Text -> m Pages.SelectVATPage
documentSelectVATPage dataDir key = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm
    db
    (profile, key)
  case output of
    Right _ -> pure $ Pages.SelectVATPage profile key "/forms/edit/simple-contract/confirm-vat/"
    Left  _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentConfirmVATPage
  :: ServerC m => FilePath -> Text -> Int -> m Pages.ConfirmVATPage
documentConfirmVATPage dataDir key rate = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm
    db
    (profile, key)
  case output of
    Right _ -> do
      pure $ Pages.ConfirmVATPage
          profile
          key
          rate
          (H.toValue $ "/forms/edit/simple-contract/" <> key <> "#panel-invoicing")
          (H.toValue $ "/echo/select-vat/" <> key)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentSimpleContractAddExpensePage
  :: ServerC m => FilePath -> Text -> m Pages.SimpleContractAddExpensePage
documentSimpleContractAddExpensePage dataDir key = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm db (profile, key)
  case output of
    Right _ -> pure $ Pages.SimpleContractAddExpensePage
      profile
      key
      Nothing
      SimpleContract.emptyAddExpense
      (H.toValue $ "/forms/edit/simple-contract/" <> key <> "#panel-expenses")
      (H.toValue $ "/echo/simple-contract/add-expense/" <> key)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

-- | Same as documentSimpleContractAddExpensePage, but use an existing form.
documentSimpleContractEditExpensePage
  :: ServerC m => FilePath -> Text -> Int -> m Pages.SimpleContractAddExpensePage
documentSimpleContractEditExpensePage dataDir key index = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm db (profile, key)
  case output of
    Right (SimpleContract.CreateContractAll _ _ _ _ _ expenses) ->
      if index > length expenses - 1
        then Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.
        else pure $ Pages.SimpleContractAddExpensePage
          profile
          key
          (Just index)
          (expenses !! index)
          (H.toValue $ "/forms/edit/simple-contract/" <> key <> "#panel-expenses")
          (H.toValue $ "/echo/simple-contract/save-expense/" <> key <> "/" <> show index)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentSimpleContractRemoveExpensePage
  :: ServerC m => FilePath -> Text -> Int -> m Pages.SimpleContractRemoveExpensePage
documentSimpleContractRemoveExpensePage dataDir key index = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm db (profile, key)
  case output of
    Right (SimpleContract.CreateContractAll _ _ _ _ _ expenses) ->
      if index > length expenses - 1
        then Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.
        else pure $ Pages.SimpleContractRemoveExpensePage
          profile
          key
          index
          (expenses !! index)
          (H.toValue $ "/echo/simple-contract/remove-expense/" <> key <> "/" <> show index)
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.

documentConfirmSimpleContractPage
  :: ServerC m => FilePath -> Text -> m Pages.ConfirmSimpleContractPage
documentConfirmSimpleContractPage dataDir key = do
  profile <- readJson $ dataDir </> "alice.json"
  db      <- asks Rt._rDb
  output  <- liftIO . atomically $ Rt.readCreateSimpleContractForm
    db
    (profile, key)
  case output of
    Right contractAll -> do
      let role = SimpleContract._createContractRole
            $ SimpleContract._createContractType contractAll
      case Pages.lookupRoleLabel role of
        Just roleLabel -> pure $ Pages.ConfirmSimpleContractPage
          profile
          key
          contractAll
          roleLabel
          (Just . H.toValue $ "/forms/edit/simple-contract/" <> key)
          "/echo/submit-simple-contract"
        Nothing -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack role -- TODO Specific error.
    Left _ -> Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack key -- TODO Specific error.


--------------------------------------------------------------------------------
-- TODO Validate the filename (e.g. this can't be a path going up).
documentProfilePage :: ServerC m => FilePath -> FilePath -> m Pages.ProfileView
documentProfilePage dataDir filename = do
  profile <- readJson $ dataDir </> filename
  pure $ Pages.ProfileView profile (Just "#")


--------------------------------------------------------------------------------
-- TODO Validate the filename (e.g. this can't be a path going up).
documentEntityPage :: ServerC m => FilePath -> FilePath -> m Pages.EntityView
documentEntityPage dataDir filename = do
  entity <- readJson $ dataDir </> filename
  pure $ Pages.EntityView Nothing entity (Just "#")


--------------------------------------------------------------------------------
-- TODO Validate the filename (e.g. this can't be a path going up).
documentUnitPage :: ServerC m => FilePath -> FilePath -> m Pages.UnitView
documentUnitPage dataDir filename = do
  unit <- readJson $ dataDir </> filename
  pure $ Pages.UnitView Nothing unit (Just "#")


--------------------------------------------------------------------------------
-- TODO Validate the filename (e.g. this can't be a path going up).
documentContractPage
  :: ServerC m => FilePath -> FilePath -> m Pages.ContractView
documentContractPage dataDir filename = do
  contract <- readJson $ dataDir </> filename
  pure $ Pages.ContractView contract (Just "#")


--------------------------------------------------------------------------------
-- TODO Validate the filename (e.g. this can't be a path going up).
documentInvoicePage :: ServerC m => FilePath -> FilePath -> m Pages.InvoiceView
documentInvoicePage dataDir filename = do
  invoice <- readJson $ dataDir </> filename
  pure $ Pages.InvoiceView invoice (Just "#")


--------------------------------------------------------------------------------
-- TODO When given a wrong path, e.g, in documentProfilePage above, the
-- returned HTML is not what I expect, nor the error is logged to our log files.
readJson :: (ServerC m, FromJSON a) => FilePath -> m a
readJson path = do
  content <- liftIO $ BS.readFile path
  let ma = eitherDecode content
  case ma of
    Right a -> pure a
    -- TODO Be more specific, e.g. the error can also be malformed JSON.
    Left  _ -> Errs.throwError' $ Rt.FileDoesntExistErr path


--------------------------------------------------------------------------------
-- | Run a handler, ensuring a user profile can be extracted from the
-- authentication result, or throw an error.
withUser
  :: forall m a
   . ServerC m
  => SAuth.AuthResult User.UserId
  -> (User.UserProfile -> m a)
  -> m a
withUser authResult f = withMaybeUser authResult (authFailedErr . show) f
 where
  authFailedErr = Errs.throwError' . User.UserNotFound . mappend
    "Authentication failed, please login again. Error: "

-- | Run either a handler expecting a user profile, or a normal handler,
-- depending on if a user profile can be extracted from the authentication
-- result or not.
withMaybeUser
  :: forall m a
   . ServerC m
  => SAuth.AuthResult User.UserId
  -> (SAuth.AuthResult User.UserId -> m a)
  -> (User.UserProfile -> m a)
  -> m a
withMaybeUser authResult a f = case authResult of
  SAuth.Authenticated userId -> do
    db <- asks Rt._rDb
    S.liftTxn (S.dbSelect @m @STM db (User.SelectUserById userId))
      <&> (preview $ _Right . _head)
      >>= \case
            Nothing -> do
              ML.warning
                "Cookie-based authentication succeeded, but the user ID is not found."
              authFailedErr $ "No user found with ID " <> show userId
            Just userProfile -> f userProfile
  authFailed -> a authFailed
  where authFailedErr = Errs.throwError' . User.UserNotFound

-- | Run a handler, ensuring a user profile can be obtained from the
-- given username, or throw an error.
withUserFromUsername
  :: forall m a
   . ServerC m
  => User.UserName
  -> (User.UserProfile -> m a)
  -> m a
withUserFromUsername username f = withMaybeUserFromUsername
  username
  (noSuchUserErr . show)
  f
 where
  noSuchUserErr = Errs.throwError' . User.UserNotFound . mappend
    "The given username was not found: "

-- | Run either a handler expecting a user profile, or a normal handler,
-- depending on if a user profile can be queried using the supplied username or
-- not.
withMaybeUserFromUsername
  :: forall m a
   . ServerC m
  => User.UserName
  -> (User.UserName -> m a)
  -> (User.UserProfile -> m a)
  -> m a
withMaybeUserFromUsername username a f = do
  mprofile <- Rt.withRuntimeAtomically (Rt.selectUserByUsername . Rt._rDb)
                                       username
  maybe (a username) f mprofile


--------------------------------------------------------------------------------
-- | Run a handler, ensuring a user profile can be obtained from the given
-- username, or throw an error.
withEntityFromName
  :: forall m a . ServerC m => Text -> (Legal.Entity -> m a) -> m a
withEntityFromName name f = withMaybeEntityFromName name
                                                    (noSuchUserErr . show) -- TODO entity, not user
                                                    f
 where
  noSuchUserErr = Errs.throwError' . User.UserNotFound . mappend
    "The given username was not found: "

-- | Run either a handler expecting an entity, or a normal handler, depending
-- on if entity can be queried using the supplied name or not.
withMaybeEntityFromName
  :: forall m a
   . ServerC m
  => Text
  -> (Text -> m a)
  -> (Legal.Entity -> m a)
  -> m a
withMaybeEntityFromName name a f = do
  mentity <- Rt.withRuntimeAtomically (Rt.selectEntityBySlug . Rt._rDb) name
  maybe (a name) f mentity


--------------------------------------------------------------------------------
-- | Run a handler, ensuring a business unit can be obtained from the given
-- ame, or throw an error.
withUnitFromName
  :: forall m a . ServerC m => Text -> (Business.Entity -> m a) -> m a
withUnitFromName name f = withMaybeUnitFromName name
                                                (noSuchUserErr . show) -- TODO unit, not user
                                                f
 where
  noSuchUserErr = Errs.throwError' . User.UserNotFound . mappend
    "The given username was not found: "

-- | Run either a handler expecting a unit, or a normal handler, depending
-- on if a unit can be queried using the supplied name or not.
withMaybeUnitFromName
  :: forall m a
   . ServerC m
  => Text
  -> (Text -> m a)
  -> (Business.Entity -> m a)
  -> m a
withMaybeUnitFromName name a f = do
  munit <- Rt.withRuntimeAtomically (Rt.selectUnitBySlug . Rt._rDb) name
  maybe (a name) f munit


--------------------------------------------------------------------------------
showRun :: ServerC m => SAuth.AuthResult User.UserId -> m Pages.RunPage
showRun authResult = withMaybeUser
  authResult
  (\_ -> pure $ Pages.RunPage Nothing "/a/run")
  (\profile -> pure $ Pages.RunPage (Just profile) "/a/run")

handleRun
  :: ServerC m
  => SAuth.AuthResult User.UserId
  -> Data.Command
  -> m Pages.EchoPage
handleRun authResult (Data.Command cmd) = withMaybeUser
  authResult
  (\_ -> run Nothing >>= pure . Pages.EchoPage)
  (\profile -> run (Just profile) >>= pure . Pages.EchoPage)
 where
  run mprofile = do
    runtime <- ask
    output <- liftIO $ Inter.interpret' runtime username "/tmp/nowhere" [cmd] 0
    let (_, ls) = Inter.formatOutput output
    pure $ unlines ls
    where
      username = maybe (User.UserName "nobody") (User._userCredsName . User._userProfileCreds) mprofile

showState :: ServerC m => m Pages.EchoPage
showState = do
  stmDb <- asks Rt._rDb
  db    <- readFullStmDbInHask stmDb
  pure . Pages.EchoPage $ show db

-- TODO The passwords are displayed in clear. Would be great to have the option
-- to hide/show them.
showStateAsJson
  :: ServerC m => m (JP.PrettyJSON '[ 'JP.DropNulls] (HaskDb Rt.Runtime))
showStateAsJson = do
  stmDb <- asks Rt._rDb
  db    <- readFullStmDbInHask stmDb
  pure $ JP.PrettyJSON db


--------------------------------------------------------------------------------
-- | Serve the static files for the documentation. This also provides a custom
-- 404 fallback.
serveDocumentation :: ServerC m => FilePath -> Tagged m Application
serveDocumentation root = serveDirectoryWith settings
 where
  settings = (defaultWebAppSettings root)
    { ss404Handler = Just custom404
    , ssLookupFile = webAppLookup hashFileIfExists root
    }

custom404 :: Application
custom404 _request sendResponse = sendResponse $ Wai.responseLBS
  HTTP.status404
  [("Content-Type", "text/html; charset=UTF-8")]
  (renderMarkup $ H.toMarkup Pages.NotFoundPage)


--------------------------------------------------------------------------------
-- | Serve example data as JSON files.
serveData path = serveDirectoryWith settings
 where
  settings = (defaultWebAppSettings path) { ss404Handler = Just custom404 }


--------------------------------------------------------------------------------
-- | Serve example data as UBL JSON files.
-- `schema` can be for instance `"PartyLegalEntity"`.
serveUBL dataDir "PartyLegalEntity" filename = do
  value <- readJson $ dataDir </> filename
  pure . Legal.toUBL $ value

serveUBL _ schema _ =
  Errs.throwError' . Rt.FileDoesntExistErr $ T.unpack schema -- TODO Specific error.


--------------------------------------------------------------------------------
-- | Serve errors intentionally. Only 500 for now.
serveErrors :: ServerC m => m Text
serveErrors = Errs.throwError' $ ServerErr "Intentional 500."

errorFormatters :: Server.ErrorFormatters
errorFormatters = defaultErrorFormatters


--------------------------------------------------------------------------------
-- | Serve the pages under a namespace. TODO Currently the namespace is
-- hard-coded to "alice" and "mila" for usernames, and "alpha" for business
-- unit names.
serveNamespace
  :: ServerC m
  => Text
  -> SAuth.AuthResult User.UserId
  -> m (PageEither Pages.PublicProfileView Pages.UnitView)
serveNamespace name authResult = withMaybeUserFromUsername
  (User.UserName name)
  withName
  withTargetProfile

 where
  withName (User.UserName name) = SS.P.PageR <$> serveUnit authResult name
  withTargetProfile targetProfile = withMaybeUser
    authResult
    (const . pure . SS.P.PageL $ Pages.PublicProfileView Nothing targetProfile)
    (\profile ->
      pure . SS.P.PageL $ Pages.PublicProfileView (Just profile) targetProfile
    )

-- | This try to serve a namespace profile (i.e. a user profile or a business
-- unit profile). If such profile can't be found, this falls back to serving
-- static assets (including documentation pages).
serveNamespaceOrStatic
  :: forall m
   . ServerC m
  => (forall x . m x -> Handler x) -- ^ Natural transformation to transform an
  -> Server.Context ServerSettings
  -> SAuth.JWTSettings
  -> Command.ServerConf
  -> FilePath
  -> Text
  -> Tagged m Application
serveNamespaceOrStatic natTrans ctx jwtSettings Command.ServerConf {..} root name
  = Tagged $ \req sendRes ->
    let authRes =
          -- see: https://hackage.haskell.org/package/servant-auth-server-0.4.6.0/docs/Servant-Auth-Server-Internal-Types.html#t:AuthCheck
          SAuth.runAuthCheck cookieAuthCheck req

        -- Try getting a user or business unit profile from the namespace.
        tryNamespace =
          Server.runHandler . natTrans $ serveNamespace name =<< liftIO authRes

        pureApplication res =
          Server.serveWithContext (Proxy @NamespaceAPI) ctx
            . hoistServerWithContext (Proxy @NamespaceAPI)
                                     settingsProxy
                                     natTrans
            $ pure res
    in
    -- now we are in IO
        tryNamespace >>= \case
        -- No such user: try to serve documentation.
        -- We ignore server errors for now. TODO Do this only for 404.
          Left _ ->
            -- Unpack the documentation `Application` from `Data.Tagged` and
            -- apply it to our request and response send function. The captured
            -- name is put back into the pathInfo so that serveDocumentation
            -- truly acts form `/`.
            let Tagged docApp = serveDocumentation @m root
                req'          = req { Wai.pathInfo = name : Wai.pathInfo req }
            in  docApp req' sendRes
          -- User or unit found, return it.
          Right res -> pureApplication res req sendRes
 where
  cookieAuthCheck = SAuth.Cookie.cookieAuthCheck _serverCookie jwtSettings

serveNamespaceDocumentation
  :: ServerC m => User.UserName -> m Pages.ProfileView
serveNamespaceDocumentation username = withUserFromUsername
  username
  (\profile -> pure $ Pages.ProfileView profile Nothing)


--------------------------------------------------------------------------------
serveEntity
  :: ServerC m => SAuth.AuthResult User.UserId -> Text -> m Pages.EntityView
serveEntity authResult name = withEntityFromName name $ \targetEntity ->
  withMaybeUser
    authResult
    (const . pure $ Pages.EntityView Nothing targetEntity Nothing)
    (\profile -> pure $ Pages.EntityView (Just profile) targetEntity (Just "#"))


--------------------------------------------------------------------------------
serveUnit
  :: ServerC m => SAuth.AuthResult User.UserId -> Text -> m Pages.UnitView
serveUnit authResult name = withUnitFromName name $ \targetUnit ->
  withMaybeUser
    authResult
    (const . pure $ Pages.UnitView Nothing targetUnit Nothing)
    (\profile -> pure $ Pages.UnitView (Just profile) targetUnit (Just "#"))


--------------------------------------------------------------------------------
-- Accept websocket connections, and keep them alive. This is used by the
-- `autoReload` element to cause a web page to auto-refresh when the connection
-- is lost, e.g. when using ghcid to re-launch the server upon changes to the
-- source code.
type WebSocketApi = "ws" :> WebSocket

websocket :: ServerC m => Connection -> m ()
websocket con =
  liftIO $ withPingThread con 30 (pure ()) $ liftIO . forM_ [1 ..] $ \i -> do
    sendTextData con (show (i :: Int) :: Text)
    threadDelay $ 60 * 1000000 -- 60 seconds


--------------------------------------------------------------------------------
newtype ServerErr = ServerErr Text
  deriving Show

instance Errs.IsRuntimeErr ServerErr where
  errCode ServerErr{} = "ERR.INTERNAL"
  httpStatus ServerErr{} = HTTP.internalServerError500
  userMessage = Just . \case
    ServerErr msg ->
      LT.toStrict . R.renderMarkup . H.toMarkup $ Pages.ErrorPage
        500
        "Internal server error"
        msg
