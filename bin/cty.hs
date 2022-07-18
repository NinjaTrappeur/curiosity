-- | This is the main server-side program to interact with the server (through
-- a UNIX-domain socket) or a state file.

{-# LANGUAGE DataKinds #-}
module Main
  ( main
  ) where

import qualified Commence.InteractiveState.Class
                                               as IS
import qualified Data.ByteString.Lazy          as BS
import qualified Data.Text                     as T
import qualified Options.Applicative           as A
import qualified Prototype.Data                as Data
import qualified Prototype.Parse               as P
import qualified Prototype.Parse2              as P
import qualified Prototype.Runtime             as Rt
import qualified Servant.Auth.Server           as Srv
import           System.Directory               ( doesFileExist )


--------------------------------------------------------------------------------
main :: IO ExitCode
main = A.execParser P.parserInfoWithTarget >>= run


--------------------------------------------------------------------------------
run :: P.CommandWithTarget -> IO ExitCode
run (P.CommandWithTarget P.Init (P.StateFileTarget path)) = do
  exists <- liftIO $ doesFileExist path
  if exists
    then do
      putStrLn @Text $ "The file '" <> T.pack path <> "' already exists."
      putStrLn @Text "Aborting."
      exitFailure
    else do
      let bs = Data.serialiseDb Data.emptyHask
      try @SomeException (BS.writeFile path bs) >>= either
        (\e -> print e >> exitFailure)
        (const $ do
          putStrLn @Text $ "State file '" <> T.pack path <> "' created."
          exitSuccess
        )

run (P.CommandWithTarget command target) = do
  case target of
    P.StateFileTarget path -> do
      jwt                     <- Srv.generateKey
      runtime@Rt.Runtime {..} <-
        Rt.boot P.defaultConf { Rt._confDbFile = Just path } jwt
          >>= either throwIO pure
      -- TODO jwt should'nt be in the runtime, but in the HTTP layer

      case command of
        P.State -> do
          output <-
            Rt.runExeAppMSafe runtime
            . IS.execVisualisation
            $ Data.VisualiseFullStmDb
          print output
        P.SelectUser select -> do
          output <-
            Rt.runExeAppMSafe runtime
            . IS.execVisualisation
            $ Data.VisualiseUser select
          print output
        P.UpdateUser update -> do
          output <-
            Rt.runExeAppMSafe runtime . IS.execModification $ Data.ModifyUser
              update
          print output
        _ -> do
          putStrLn @Text $ "Unhandled command " <> show command
          exitFailure

      Rt.powerdown runtime
      -- TODO shutdown runtime, loggers, save state, ...
      exitSuccess

    P.UnixDomainTarget _ -> do
      putStrLn @Text "Unimplemented: --socket, a.k.a UnixDomainTarget"
      exitFailure
