module Prototype.Exe.DataSpec
  ( spec
  ) where

import           Prototype.Exe.Data
import           Prototype.Exe.Data.User
import qualified Prototype.Exe.Data.UserSpec   as US
import           Test.Hspec
import qualified Test.QuickCheck               as Q

spec :: Spec
spec = do
  describe "Parsing visualisations" $ do
    -- FIXME add tests for TODO
    it "Should parse UserLogin-visualisations." $ Q.property userVizParseProp
    it "Should parse SelectUserById-visualisation."
      $ Q.property selectUserByIdVizParseProp

  describe "Parsing modifications" $ do
    -- FIXME add tests for TODO
    it "Should parse UserCreate-modifications."
      $ Q.property createUserModParseProp
    it "Should parse UserDelete-modifications."
      $ Q.property deleteUserModParseProp

userVizParseProp :: UserName -> Password -> Bool
userVizParseProp userName pwd =
  let input = "viz user " <> US.showUserLogin userName pwd
  in  isRight $ parseViz input

selectUserByIdVizParseProp :: UserId -> Bool
selectUserByIdVizParseProp userId =
  let input = "viz user " <> US.showSelectUserById userId
  in  isRight $ parseViz input

createUserModParseProp :: UserCreds -> UserName -> Bool
createUserModParseProp creds userName =
  let input = "mod user " <> US.showUserCreate creds userName
  in  isRight $ parseMod input

deleteUserModParseProp :: UserId -> Bool
deleteUserModParseProp userId =
  let input = "mod user " <> US.showUserDelete userId
  in  isRight $ parseMod input
