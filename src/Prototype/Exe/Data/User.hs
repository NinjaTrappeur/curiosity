{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds #-}
{- |
Module: Prototype.Exe.Data.User
Description: User related datatypes
-}
module Prototype.Exe.Data.User
  ( Signup(..)
  , UserCreds(..)
  , userCredsName
  , userCredsPassword
  , UserProfile'(..)
  , UserProfile
  , userProfileCreds
  , userProfileId
  , userProfileDisplayName
  , userProfileEmailAddr
  , UserId(..)
  , genRandomUserId
  , UserName(..)
  , Password(..)
  -- * Export all DB ops.
  , Storage.DBUpdate(..)
  , Storage.DBSelect(..)
  -- ** Parsers
  , dbUpdateParser
  , dbSelectParser
  , userIdParser
  , userNameParser
  , userPasswordParser
  -- * Errors
  , UserErr(..)
  ) where

import qualified Commence.Runtime.Errors       as Errs
import qualified Commence.Runtime.Storage      as Storage
import qualified Commence.Types.Secret         as Secret
import qualified Commence.Types.Wrapped        as W
import           Control.Lens
import           Data.Aeson
import qualified Data.Char                     as Char
import qualified Data.Text                     as T
import qualified Network.HTTP.Types            as HTTP
import qualified Prototype.Exe.Repl.Parse      as P
import qualified Servant.Auth.Server           as SAuth
import qualified Smart.Server.Page.Navbar      as Nav
import qualified System.Random                 as Rand
import qualified Text.Blaze.Html5              as H
import           Text.Blaze.Html5               ( (!) )
import qualified Text.Blaze.Html5.Attributes   as A
import           Web.FormUrlEncoded             ( FromForm(..)
                                                , parseUnique
                                                )
import           Web.HttpApiData                ( FromHttpApiData(..) )


--------------------------------------------------------------------------------
-- | Represents the input data used for user registration.
data Signup = Signup
  { username :: UserName
  , password :: Password
  , email    :: UserEmailAddr
  }
  deriving (Generic, Eq, Show)

instance FromForm Signup where
  fromForm f =
    Signup
      <$> parseUnique "username"   f
      <*> parseUnique "password"   f
      <*> parseUnique "email-addr" f

-- | User's credentials.
data UserCreds = UserCreds
  { _userCredsName     :: UserName
  , _userCredsPassword :: Password
  }
  deriving (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

instance FromForm UserCreds where
  fromForm f =
    UserCreds <$> parseUnique "username" f <*> parseUnique "password" f

data UserProfile' creds userDisplayName userEmailAddr = UserProfile
  { _userProfileId          :: UserId
  , _userProfileCreds       :: creds -- ^ Users credentials
  , _userProfileDisplayName :: userDisplayName -- ^ User's human friendly name
  , _userProfileEmailAddr   :: userEmailAddr -- ^ User's email address
  }
  deriving (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

type UserProfile = UserProfile' UserCreds UserDisplayName UserEmailAddr

-- | The username is an identifier (i.e. it is unique).
newtype UserName = UserName Text
                 deriving (Eq, Show, IsString, FromJSON , ToJSON) via Text
                 deriving (FromHttpApiData, FromForm) via W.Wrapped "username" Text

newtype UserDisplayName = UserDisplayName Text
                 deriving (Eq, Show, IsString, FromJSON , ToJSON) via Text
                 deriving (FromHttpApiData, FromForm) via W.Wrapped "display-name" Text

newtype UserEmailAddr = UserEmailAddr Text
                 deriving (Eq, Show, IsString, FromJSON , ToJSON) via Text
                 deriving (FromHttpApiData, FromForm) via W.Wrapped "email-addr" Text

newtype Password = Password (Secret.Secret '[ 'Secret.ToJSONExp] Text)
                 deriving (Eq, IsString) via Text
                 deriving ( FromHttpApiData
                          , FromJSON
                          , ToJSON
                          ) via (Secret.Secret '[ 'Secret.ToJSONExp] Text)
                 deriving stock Show
                 deriving FromForm via W.Wrapped "password" Text

-- | Record ID of the form USER-xxx.
newtype UserId = UserId Text
               deriving (Eq, Show, SAuth.ToJWT, SAuth.FromJWT)
               deriving (IsString, FromHttpApiData, FromJSON, ToJSON) via Text
               deriving FromForm via W.Wrapped "user-id" Text

-- | Randomly generated and character based user-id.
-- TODO Generate this sequentially instead.
genRandomUserId :: forall m . MonadIO m => Int -> m UserId
genRandomUserId len =
  liftIO
    $   UserId
    .   T.pack
    .   ("USER-" <>)
    .   take (abs len)
    .   Rand.randomRs ('0', '9')
    <$> Rand.getStdGen

instance Nav.IsNavbarContent UserProfile where
  navbarMarkup UserProfile {..} = do
    greeting
    editProfileLink
    H.hr
   where
    greeting =
      H.div . H.text $ T.unwords ["Hi", _userProfileDisplayName ^. coerced]
    editProfileLink = H.a ! A.href "/private/user/profile" $ "Edit profile"

instance Storage.DBIdentity UserProfile where
  type DBId UserProfile = UserId
  dbId = _userProfileId

instance Storage.DBStorageOps UserProfile where
  data DBUpdate UserProfile =
    UserCreate UserProfile
    | UserCreateGeneratingUserId UserName Password UserEmailAddr
    | UserDelete UserId
    | UserPasswordUpdate UserId Password
    deriving (Show, Eq)

  data DBSelect UserProfile =
    -- | Attempt a user-login using the more ambiguous but more friendly
    -- `UserName` and `Password.
    UserLoginWithUserName UserName Password
    -- | Select a user with a known `UserId`.
    | SelectUserById UserId
    -- | Select a user with `UserName`.
    | SelectUserByUserName UserName
    deriving (Show, Eq)

dbUpdateParser :: P.ParserText (Storage.DBUpdate UserProfile)
dbUpdateParser = P.tryAlts
  [userCreate, userCreateGeneratingUserId, userDelete, userUpdate]
 where
  userCreate =
    P.withTrailSpaces "UserCreate" *> fmap UserCreate userProfileParser
  userCreateGeneratingUserId =
    P.withTrailSpaces "UserCreateGeneratingUserId"
      *> (   UserCreateGeneratingUserId
         <$> userNameParser
         <*> userPasswordParser
         <*> userEmailAddrParser
         )
  userDelete = P.withTrailSpaces "UserDelete" *> userIdParser <&> UserDelete
  userUpdate =
    P.withTrailSpaces "UserPasswordUpdate"
      *> (   UserPasswordUpdate
         <$> (userIdParser <* P.space)
         <*> userPasswordParser
         )

-- | For simplicity, we keep the parsers close to the actual data-constructors.
dbSelectParser :: P.ParserText (Storage.DBSelect UserProfile)
dbSelectParser = P.tryAlts
  [userLoginWithUserName, selectUserById, selectUsersByUserName]
 where
  userLoginWithUserName =
    P.withTrailSpaces "UserLoginWithUserName"
      *> (   UserLoginWithUserName
         <$> (userNameParser <* P.space)
         <*> userPasswordParser
         )
  selectUserById =
    P.withTrailSpaces "SelectUserById" *> userIdParser <&> SelectUserById
  selectUsersByUserName =
    P.withTrailSpaces "SelectUserByUserName"
      *>  userNameParser
      <&> SelectUserByUserName

-- | The UserId has to be non-empty ascii character
userIdParser :: P.ParserText UserId
userIdParser = UserId <$> P.punctuated P.alphaNumText

userNameParser :: P.ParserText UserName
userNameParser = UserName <$> P.punctuated P.takeRest

userDisplayNameParser :: P.ParserText UserDisplayName
userDisplayNameParser = UserDisplayName <$> P.punctuated P.takeRest

userEmailAddrParser :: P.ParserText UserEmailAddr
userEmailAddrParser = UserEmailAddr <$> P.punctuated P.takeRest

-- | For the password, we want to consume everything within the punctuations.
userPasswordParser :: P.ParserText Password
userPasswordParser = Password . Secret.Secret <$> P.punctuated
  (P.takeWhile1P (Just "Password") (not . Char.isPunctuation))

userProfileParser :: P.ParserText UserProfile
userProfileParser =
  UserProfile
    <$> (userIdParser <* P.space)
    <*> (userCredsParser <* P.space)
    <*> (userDisplayNameParser <* P.space)
    <*> (userEmailAddrParser <* P.space)

userCredsParser =
  UserCreds <$> (userNameParser <* P.space) <*> userPasswordParser

data UserErr = UserExists Text
             | UserNotFound Text
             | IncorrectPassword Text
             deriving Show

instance Errs.IsRuntimeErr UserErr where
  errCode = errCode' . \case
    UserExists{}        -> "USER_EXISTS"
    UserNotFound{}      -> "USER_NOT_FOUND"
    IncorrectPassword{} -> "INCORRECT_PASSWORD"
    where errCode' = mappend "ERR.USER."

  httpStatus = \case
    UserExists{}        -> HTTP.conflict409
    UserNotFound{}      -> HTTP.notFound404
    IncorrectPassword{} -> HTTP.unauthorized401

  userMessage = Just . \case
    UserExists        msg -> msg
    UserNotFound      msg -> msg
    IncorrectPassword msg -> msg

makeLenses ''UserCreds
makeLenses ''UserProfile'
