{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE DataKinds #-}
module Curiosity.Command
  ( Command(..)
  , QueueName(..)
  , Queues(..)
  , ParseConf(..)
  , CommandWithTarget(..)
  , CommandTarget(..)
  , CommandUser(..)
  , ObjectType(..)
  , parserInfo
  , parserInfoWithTarget
  ) where

import qualified Commence.Runtime.Storage      as S
import qualified Curiosity.Data.User           as U
import qualified Curiosity.Parse               as P
import qualified Data.Text                     as T
import qualified Options.Applicative           as A


--------------------------------------------------------------------------------
-- | Describes the command available from the command-line with `cty`, or
-- within the UNIX-domain socket server, `cty-sock`, or the `cty-repl-2` REPL.
data Command =
    Layout
    -- ^ Display the routing layout of the web server.
  | Init
    -- ^ Initialise a new, empty state file.
  | Repl P.Conf
    -- ^ Run a REPL.
  | Serve P.Conf P.ServerConf
    -- ^ Run an HTTP server.
  | Run P.Conf FilePath
    -- ^ Interpret a script.
  | Parse ParseConf
    -- ^ Parse a single command.
  | State Bool
    -- ^ Show the full state. If True, use Haskell format instead of JSON.
  | CreateUser U.Signup
  | SelectUser Bool U.UserId
    -- ^ Show a give user. If True, use Haskell format instead of JSON.
  | FilterUsers U.Predicate
  | UpdateUser (S.DBUpdate U.UserProfile)
  | SetUserEmailAddrAsVerified U.UserId
    -- ^ High-level operations on users.
  | ViewQueue QueueName
    -- ^ View queue. The queues can be filters applied to objects, not
    -- necessarily explicit list in database.
  | ViewQueues Queues
  | ShowId Text
    -- ^ If not a command per se, assume it's an ID to be looked up.
  deriving Show

data QueueName = EmailAddrToVerify
  deriving (Eq, Show)

data Queues = CurrentUserQueues | AllQueues | AutomatedQueues | ManualQueues | UserQueues U.UserName
  deriving (Eq, Show)

data ParseConf =
    ConfCommand Text
  | ConfFileName FilePath
  | ConfStdin
  | ParseObject ObjectType FilePath
  deriving Show

data ObjectType = ParseState | ParseUser
  deriving Show

-- | The same commands, defined above, can be used within the UNIX-domain
-- socket server, `cty-sock`, but also from a real command-line tool, `cty`.
-- In the later case, a user might want to direct the command-line tool to
-- interact with a server, or a local state file. This data type is meant to
-- augment the above commands with such options. In addition, the command is
-- supposed to be performed by the given user. This is to be set by SSH's
-- ForceCommand.
data CommandWithTarget = CommandWithTarget Command CommandTarget CommandUser
  deriving Show

data CommandTarget = MemoryTarget | StateFileTarget FilePath | UnixDomainTarget FilePath
  deriving Show

-- Running a command can be done by passing explicitely a user (this is
-- intended to be used behind SSH, or possibly when administring the system)
-- or, for convenience, by taking the UNIX login from the current session.
data CommandUser = UserFromLogin | User U.UserName
  deriving Show


--------------------------------------------------------------------------------
parserInfo :: A.ParserInfo Command
parserInfo =
  A.info (parser <**> A.helper)
    $  A.fullDesc
    <> A.header "cty-sock - Curiosity's UNIX-domain socket server"
    <> A.progDesc
         "Curiosity is a prototype application to explore the design space \
        \of a web application for Smart.\n\n\
        \cty-sock offers a networked REPL exposed over a UNIX-domain socket."

parserInfoWithTarget :: A.ParserInfo CommandWithTarget
parserInfoWithTarget =
  A.info (parser' <**> A.helper)
    $  A.fullDesc
    <> A.header "cty - Curiosity's main server-side program"
    <> A.progDesc
         "Curiosity is a prototype application to explore the design space \
        \of a web application for Smart.\n\n\
        \cty offers a command-line interface against a running server or \
        \a state file."
 where
  parser' = do
    user <-
      A.option (A.eitherReader (Right . User . U.UserName . T.pack))
      $  A.short 'u'
      <> A.long "user"
      <> A.value UserFromLogin
      <> A.help "A username performing this command."
      <> A.metavar "USERNAME"
    target <-
      (A.flag' MemoryTarget $ A.short 'm' <> A.long "memory" <> A.help
        "Don't use a state file or a UNIX-domain socket."
      )
      <|> StateFileTarget
      <$> (  A.strOption
          $  A.short 's'
          <> A.long "state"
          <> A.value "state.json"
          <> A.help "A state file. Default is 'state.json'."
          <> A.metavar "FILEPATH"
          )
      <|> UnixDomainTarget
      <$> (  A.strOption
          $  A.short 't'
          <> A.long "socket"
          <> A.help "A UNIX-domain socket"
          <> A.metavar "FILEPATH"
          )
    command <- parser
    return $ CommandWithTarget command target user


--------------------------------------------------------------------------------
parser :: A.Parser Command
parser =
  A.subparser
      (  A.command
          "layout"
          ( A.info (parserLayout <**> A.helper)
          $ A.progDesc "Display the routing layout of the web server"
          )

      <> A.command
           "init"
           ( A.info (parserInit <**> A.helper)
           $ A.progDesc "Initialise a new, empty state file"
           )

      <> A.command
           "repl"
           (A.info (parserRepl <**> A.helper) $ A.progDesc "Start a REPL")

      <> A.command
           "serve"
           ( A.info (parserServe <**> A.helper)
           $ A.progDesc "Run the Curiosity HTTP server"
           )

      <> A.command
           "run"
           (A.info (parserRun <**> A.helper) $ A.progDesc "Interpret a script"
           )

      <> A.command
           "parse"
           ( A.info (parserParse <**> A.helper)
           $ A.progDesc "Parse a single command"
           )

      <> A.command
           "state"
           ( A.info (parserState <**> A.helper)
           $ A.progDesc "Show the full state"
           )

      <> A.command
           "user"
           ( A.info (parserUser <**> A.helper)
           $ A.progDesc "User-related commands"
           )

      <> A.command
           "queue"
           ( A.info (parserQueue <**> A.helper)
           $ A.progDesc "Display a queue's content"
           )

      <> A.command
           "queues"
           ( A.info (parserQueues <**> A.helper)
           $ A.progDesc "Display all queues content"
           )
      )
    <|> parserShowId

parserLayout :: A.Parser Command
parserLayout = pure Layout

parserInit :: A.Parser Command
parserInit = pure Init

parserRepl :: A.Parser Command
parserRepl = Repl <$> P.confParser

parserServe :: A.Parser Command
parserServe = Serve <$> P.confParser <*> P.serverParser

parserRun :: A.Parser Command
parserRun = Run <$> P.confParser <*> A.argument
  A.str
  (A.metavar "FILE" <> A.help "Script to run.")

parserParse :: A.Parser Command
parserParse = Parse <$> (parserCommand <|> parserObject <|> parserFileName)

parserCommand :: A.Parser ParseConf
parserCommand = ConfCommand <$> A.strOption
  (A.long "command" <> A.short 'c' <> A.metavar "COMMAND" <> A.help
    "Command to parse."
  )

parserFileName :: A.Parser ParseConf
parserFileName = A.argument (A.eitherReader f)
                            (A.metavar "FILE" <> A.help "Command to parse.")
 where
  f "-" = Right ConfStdin
  f s   = Right $ ConfFileName s

parserObject :: A.Parser ParseConf
parserObject =
  ParseObject
    <$> A.option
          (A.eitherReader f)
          (A.long "object" <> A.metavar "TYPE" <> A.help
            "Type of the object to parse."
          )
    <*> A.argument A.str (A.metavar "FILE" <> A.help "Object to parse.")
 where
  f "state" = Right ParseState
  f "user"  = Right ParseUser
  f _       = Left "Unrecognized object type."

parserState :: A.Parser Command
parserState = State <$> A.switch
  (A.long "hs" <> A.help "Use the Haskell format (default is JSON).")

parserUser :: A.Parser Command
parserUser = A.subparser
  (  A.command
      "create"
      (A.info (parserCreateUser <**> A.helper) $ A.progDesc "Create a new user")
  <> A.command
       "delete"
       (A.info (parserDeleteUser <**> A.helper) $ A.progDesc "Delete a user")
  <> A.command
       "get"
       (A.info (parserGetUser <**> A.helper) $ A.progDesc "Select a user")
  <> A.command
       "do"
       ( A.info (parserUserLifeCycle <**> A.helper)
       $ A.progDesc "Perform a high-level operation on a user"
       )
  )

parserCreateUser :: A.Parser Command
parserCreateUser = do
  username   <- A.argument A.str (A.metavar "USERNAME" <> A.help "A username")
  password   <- A.argument A.str (A.metavar "PASSWORD" <> A.help "A password")
  email <- A.argument A.str (A.metavar "EMAIL" <> A.help "An email address")
  tosConsent <- A.switch
    (  A.long "accept-tos"
    <> A.help "Indicate if the user being created consents to the TOS."
    )
  return $ CreateUser $ U.Signup username password email tosConsent

parserDeleteUser :: A.Parser Command
parserDeleteUser = UpdateUser . U.UserDelete . U.UserId <$> A.argument
  A.str
  (A.metavar "USER-ID" <> A.help "A user ID")

parserGetUser :: A.Parser Command
parserGetUser =
  SelectUser
    <$> A.switch
          (A.long "hs" <> A.help "Use the Haskell format (default is JSON).")
    <*> A.argument A.str (A.metavar "USER-ID" <> A.help "A user ID")

parserUserLifeCycle :: A.Parser Command
parserUserLifeCycle = A.subparser $ A.command
  "set-email-addr-as-verified"
  ( A.info (p <**> A.helper)
  $ A.progDesc "Perform a high-level operation on a user"
  )
 where
  p = SetUserEmailAddrAsVerified
    <$> A.argument A.str (A.metavar "USER-ID" <> A.help "A user ID")

-- TODO I'm using subcommands to have all queue names appear in `--help` but
-- the word COMMAND seems wrong:
--
--     cty queue --help
--     Usage: <interactive> queue COMMAND
--       Display a queue's content
--
--     Available options:
--       -h,--help                Show this help text
--
--     Available commands:
--       user-email-addr-to-verify
parserQueue :: A.Parser Command
parserQueue = A.subparser $ A.command
  "user-email-addr-to-verify"
  ( A.info (p <**> A.helper)
  $ A.progDesc
      "Show users with an email address that need verification. \
      \Use `cty user do set-email-addr-as-verified` to mark an email address \
      \as verified."
  )
  where p = pure $ ViewQueue EmailAddrToVerify

parserQueues :: A.Parser Command
parserQueues =
  ViewQueues
    <$> (   (A.flag' CurrentUserQueues $ A.long "current-user" <> A.help
              "Display the queues of the current user. This is the default."
            )
        <|> (A.flag' AllQueues $ A.long "all" <> A.help
              "Display all the queues of the system."
            )
        <|> (  A.flag' AutomatedQueues
            $  A.long "automated"
            <> A.help
                 "Display the queues that can be handled automatically by the system."
            )
        <|> (A.flag' ManualQueues $ A.long "manual" <> A.help
              "Display the queues that can be handled by users."
            )
        <|> (  A.option
                (A.eitherReader (Right . UserQueues . U.UserName . T.pack))
            $  A.long "from"
            <> A.value CurrentUserQueues
            <> A.help "Display the queues of the give user."
            <> A.metavar "USERNAME"
            )
        )

parserShowId :: A.Parser Command
parserShowId =
  ShowId <$> A.argument A.str (A.metavar "ID" <> A.help "An object ID")
