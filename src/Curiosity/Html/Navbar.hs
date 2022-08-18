{- |
Module: Curiosity.Html.Navbar
Description: A navigation bar for Curiosity.
-}
module Curiosity.Html.Navbar
  ( exampleNavbarAlt
  ) where

import           Smart.Html.Avatar
import           Smart.Html.Navbar


--------------------------------------------------------------------------------
exampleNavbarAlt :: Navbar
exampleNavbarAlt = Navbar [] [userEntry]

userEntry = UserEntry userEntries NoAvatarImage

userEntries =
  [ SubEntry "Settings" "/settings/profile" False
  , Divider
  -- TODO: change to `POST` in the future. 
  , SubEntry "Sign out"   "/a/logout"       False
  ]
