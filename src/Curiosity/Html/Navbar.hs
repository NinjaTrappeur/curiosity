{- |
Module: Curiosity.Html.Navbar
Description: A navigation bar for Curiosity.
-}
module Curiosity.Html.Navbar
  ( navbar
  ) where

import           Smart.Html.Avatar
import qualified Smart.Html.Navbar             as Navbar
import           Smart.Html.Shared.Html.Icons


--------------------------------------------------------------------------------
navbar :: Text -> Navbar.Navbar
navbar name = Navbar.Navbar [] [helpEntry, plusEntry, userEntry name]

userEntry :: Text -> Navbar.RightEntry
userEntry name = Navbar.UserEntry (userEntries name) NoAvatarImage

userEntries :: Text -> [Navbar.SubEntry]
userEntries name =
  [ Navbar.SignedInAs name
  , Navbar.Divider
  , Navbar.SubEntry "Settings" "/settings/profile" False
  , Navbar.Divider
  -- TODO: change to `POST` in the future. 
  , Navbar.SubEntry "Sign out" "/a/logout" False
  ]

helpEntry :: Navbar.RightEntry
helpEntry = Navbar.IconEntry divIconCircleHelp helpEntries

helpEntries :: [Navbar.SubEntry]
helpEntries = [Navbar.SubEntry "Documentation" "/documentation" False]

plusEntry :: Navbar.RightEntry
plusEntry = Navbar.IconEntry divIconAdd plusEntries

plusEntries :: [Navbar.SubEntry]
plusEntries =
  [ Navbar.SubEntry "New invoice" "#" False
  , Navbar.SubEntry "New contract" "#" False
  , Navbar.Divider
  , Navbar.SubEntry "New business entity" "#" False
  , Navbar.SubEntry "New legal entity" "/new/entity" False
  ]
