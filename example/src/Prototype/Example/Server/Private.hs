{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DataKinds, TypeOperators #-}
{- |
Module: Prototype.Example.Server.Private
Description: Private endpoints

Contains the public endpoints for the example server.
We're using PackageImports here on purpose: this includes imports from @start-servant@ and those imports are tagged for readability
and predictability on where these modules come from.

-}
module Prototype.Example.Server.Private
  ( Private
  , privateT
  , PrivateServerC
  ) where

import "exceptions" Control.Monad.Catch         ( MonadMask )
import qualified "start-servant" MultiLogging  as ML
import qualified Prototype.Example.Data.User   as User
import qualified Prototype.Example.Runtime     as Rt
import qualified Prototype.Example.Server.Private.Auth
                                               as Auth
import qualified Prototype.Example.Server.Private.Pages
                                               as Pages
import qualified Prototype.Runtime.Errors      as Errs
import qualified Prototype.Runtime.Storage     as S
import qualified "start-servant" Prototype.Server.New.Page
                                               as SS.P
import           Servant
import qualified Servant.Auth.Server           as SAuth
import qualified Servant.HTML.Blaze            as B

type PrivateServerC m
  = ( MonadMask m
    , ML.MonadAppNameLogMulti m
    , S.DBStorage m User.UserProfile
    , MonadReader Rt.Runtime m
    , MonadIO m
    )

-- | The private API with authentication.
type Private = Auth.UserAuthentication :> UserPages
type UserPages
  = "welcome" :> Get '[B.HTML] (SS.P.Page 'SS.P.Authd User.UserProfile Pages.WelcomePage)

privateT :: forall m . PrivateServerC m => ServerT Private m
privateT authResult = showWelcomePage
 where
  showWelcomePage =
    withUser $ \profile -> pure $ SS.P.AuthdPage profile Pages.WelcomePage
  -- extract the user from the authentication result or throw an error.
  withUser f = case authResult of
    SAuth.Authenticated userId ->
      S.dbSelect (User.SelectUserById userId) <&> headMay >>= \case
        Nothing -> authFailedErr $ "No user found by ID = " <> show userId
        Just userProfile -> f userProfile
    authFailed -> authFailedErr $ show authFailed
    where authFailedErr = Errs.throwError' . User.UserNotFound
  -- (SAuth.Authenticated User.UserProfile {..})

