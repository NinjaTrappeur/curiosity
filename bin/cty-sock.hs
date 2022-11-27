-- | This is a simple UNIX-domain socket REPL server. The accepted commands
-- re-use the optparse-applicative parsers behind the `cty` command-line tool,
-- ensuring a similar experience. It is possible to interact with this server
-- with e.g.:
--
--   nc -U curiosity.sock

import qualified Curiosity.Command             as Command
import qualified Curiosity.Parse               as P
import qualified Curiosity.Runtime             as Rt
import qualified Data.ByteString.Char8         as B
import qualified Data.Text.Encoding            as T
import           Network.Socket
import           Network.Socket.ByteString      ( recv
                                                , sendAll
                                                )
import qualified Options.Applicative           as A


--------------------------------------------------------------------------------
main :: IO ()
main = A.execParser mainParserInfo >>= runWithConf

mainParserInfo :: A.ParserInfo P.Conf
mainParserInfo =
  A.info (P.confParser <**> A.helper)
    $  A.fullDesc
    <> A.header "cty-sock - Curiosity's UNIX-domain server"
    <> A.progDesc "TODO"

runWithConf conf = do
  putStrLn @Text "Creating runtime..."
  runtime <- Rt.bootConf conf Rt.NoThreads >>= either throwIO pure

  putStrLn @Text "Creating curiosity.sock..."
  sock <- socket AF_UNIX Stream 0
  bind sock $ SockAddrUnix "curiosity.sock"
  listen sock maxListenQueue

  putStrLn @Text "Listening on curiosity.sock..."
  server runtime sock -- TODO bracket (or catch) and close
  close sock

server runtime sock = do
  (conn, _) <- accept sock -- TODO bracket (or catch) and close too
  void $ forkFinally
    (handler runtime conn)
    (const $ putStrLn @Text "Closing connection." >> close conn)
  server runtime sock

handler runtime conn = do
  putStrLn @Text "New connection..."
  sendAll conn "Curiosity UNIX-domain socket server.\n"
  repl runtime conn

repl runtime conn = do
  msg <- recv conn 1024
  let command = map B.unpack $ B.words msg -- TODO decodeUtf8
  case command of
    _ | B.null msg -> return () -- Connection lost.
    ["quit"]       -> return ()
    []             -> repl runtime conn
    _              -> do
      let result = A.execParserPure A.defaultPrefs Command.parserInfo command
      case result of
        A.Success command -> do
          case command of
            _ -> do
              (_, output) <- Rt.handleCommand runtime "TODO" command
              mapM_ (\x -> sendAll conn (T.encodeUtf8 x <> "\n")) output
        A.Failure err -> case err of
          A.ParserFailure execFailure -> do
            let (msg, _, _) = execFailure "cty"
            sendAll conn (B.pack $ show msg <> "\n")
        A.CompletionInvoked _ -> print @IO @Text "Shouldn't happen"

      repl runtime conn
