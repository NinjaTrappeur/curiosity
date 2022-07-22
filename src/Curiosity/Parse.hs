{-# LANGUAGE ApplicativeDo #-}
module Curiosity.Parse
  ( confParser
  , replParser
  , serverParser
  , defaultConf
  , defaultServerConf
  ) where

import qualified Commence.InteractiveState.Repl
                                               as Repl
import qualified Commence.Multilogging         as ML
import           Control.Monad.Log             as L
import           Curiosity.Runtime
import           Curiosity.Server
import           Data.Default.Class
import qualified Options.Applicative           as A
import qualified Servant.Auth.Server           as Srv
import qualified System.Log.FastLogger         as FL


--------------------------------------------------------------------------------
confParser :: A.Parser Conf
confParser = do
  _confDbFile <- dbFileParser
  pure Conf
    {
      -- FIXME: ML.parseLoggingConf never terminates, should be fixed.
      _confLogging = ML.LoggingConf [FL.LogFile flspec 1024]
                                    "Curiosity"
                                    L.levelInfo-- ML.parseLoggingConf
    , ..
    }

defaultConf :: Conf
defaultConf =
  let _confDbFile = Nothing
  in  Conf
        { _confLogging = ML.LoggingConf [FL.LogFile flspec 1024]
                                        "Curiosity"
                                        L.levelInfo
        , ..
        }

defaultServerConf :: ServerConf
defaultServerConf = ServerConf
  { _serverPort          = 9000
  , _serverStaticDir     = "./_site/"
  , _serverDataDir       = "./data/"
  , _serverCookie        = Srv.defaultCookieSettings
                             { Srv.cookieIsSecure    = Srv.NotSecure
                             , Srv.cookieXsrfSetting = Nothing
                             , Srv.cookieSameSite    = Srv.SameSiteStrict
                             }
  , _serverMkJwtSettings = Srv.defaultJWTSettings
  }

flspec = FL.FileLogSpec "/tmp/curiosity.log" 5000 0

serverParser :: A.Parser ServerConf
serverParser = do
  _serverPort <- abs <$> A.option
    A.auto
    (A.long "server-port" <> A.value 9000 <> A.metavar "PORT" <> A.help
      "Port to run the HTTP server on."
    )
  _serverStaticDir <- A.strOption
    (  A.long "static-dir"
    <> A.value "./_site/"
    <> A.metavar "DIR"
    <> A.help
         "A directory served as static assets, in particular HTML \
            \documentation."
    )
  _serverDataDir <- A.strOption
    (A.long "data-dir" <> A.value "./data/" <> A.metavar "DIR" <> A.help
      "A directory containing example data."
    )

  pure ServerConf
    {
      -- FIXME: Add support for cookie-settings parsing.
      _serverCookie        = Srv.defaultCookieSettings
                               { Srv.cookieIsSecure    = Srv.NotSecure -- Use temporarily NotSecure for easier local testing with cURL.
                               , Srv.cookieXsrfSetting = Nothing -- XSRF disabled to simplify curl calls (same as start-servant)
                               , Srv.cookieSameSite    = Srv.SameSiteStrict
                               }
      -- FIXME: See if this can be customized via parsing.
    , _serverMkJwtSettings = Srv.defaultJWTSettings
    , ..
    }

replParser :: A.Parser Repl.ReplConf
replParser = do
  _replPrompt <-
    A.strOption
    $  A.long "repl-prompt"
    <> A.value (Repl._replPrompt def)
    <> A.showDefault
    <> A.metavar "PROMPT"
    <> A.help "Prompt to use for the repl"

  _replHistory <- A.switch $ A.long "repl-history-on" <> A.help
    "Flag to enable history."

  replReplExitCmds <- A.many $ A.strOption (A.long "repl-exit-cmd")

  pure Repl.ReplConf
    { _replReplExitCmds = if null replReplExitCmds
                            then ["quit"]
                            else replReplExitCmds
    , ..
    }

dbFileParser :: A.Parser (Maybe FilePath)
dbFileParser =
  A.optional $ A.strOption $ A.long "db-file" <> A.help helpTxt <> A.metavar
    "FILEPATH"
 where
  helpTxt
    = "DB file to read initial DB state from. The file may be empty or may not exist, in which case(s), the file will be \
                  \created on application exit."
