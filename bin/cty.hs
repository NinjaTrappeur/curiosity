-- | This is the main server-side program to interact with the server (through
-- a UNIX-domain socket) or a state file.
module Main
  ( main
  ) where

import qualified Curiosity.Command             as Command
import qualified Curiosity.Run                 as Run
import qualified Options.Applicative           as A


--------------------------------------------------------------------------------

main :: IO ExitCode
main = A.execParser Command.parserInfoWithTarget >>= Run.run
