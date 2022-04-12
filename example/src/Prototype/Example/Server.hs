{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DataKinds, TypeOperators #-} -- Language extensions needed for servant. 
{- |
Module: Prototype.Example.Server
Description: Server root module, split up into public and private sub-modules.

-}
module Prototype.Example.Server
  ( Example
  , exampleT
  , exampleApplication
  , runExampleServer
  ) where

import           Control.Lens
import qualified Network.Wai                   as Wai
import qualified Network.Wai.Handler.Warp      as Warp
import qualified Prototype.Example.Runtime     as Rt
import           Prototype.Example.Server.Public
                                               as Pub
import           Servant

type Example = "public" :> Pub.Public

exampleT :: forall m . Pub.PublicServerC m => ServerT Pub.Public m
exampleT = Pub.publicT

-- | Run as a Wai Application 
exampleApplication
  :: forall m
   . Pub.PublicServerC m
  => (forall x . m x -> Handler x) -- ^ Natural transformation to transform an arbitrary @m@ to a Servant @Handler@
  -> Wai.Application
exampleApplication handlerNatTrans = Servant.serve
  pubPxy
  (hoistServer pubPxy handlerNatTrans publicT {- ServerT -> Server -}
                                             )
  where pubPxy = Proxy @Example

runExampleServer
  :: forall m
   . MonadIO m
  => Rt.Runtime -- ^ Runtime to use for running the server. 
  -> m ()
runExampleServer runtime =
  let waiApp = exampleApplication @Rt.ExampleAppM
        (Rt.exampleAppMHandlerNatTrans runtime)
      port = runtime ^. Rt.rConf . Rt.confServer . coerced
  in  liftIO $ Warp.run port waiApp
