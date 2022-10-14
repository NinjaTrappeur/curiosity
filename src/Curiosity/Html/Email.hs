{- |
Module: Curiosity.Html.Email
Description: Page and components to display emails.
-}
module Curiosity.Html.Email
  ( EmailPage(..)
  , panelSentEmails
  ) where

import qualified Curiosity.Data.Email          as Email
import qualified Curiosity.Data.User           as User
import           Curiosity.Html.Misc
import qualified Smart.Html.Misc               as Misc
import qualified Text.Blaze.Html5              as H


--------------------------------------------------------------------------------
-- | The page displaye at @/emails@ to show all enqueued emails.
data EmailPage = EmailPage
  { _emailPageUser   :: Maybe User.UserProfile
    -- ^ The logged-in user, if any.
  , _emailPageEmails :: [Email.Email]
    -- ^ All enqueued emails.
  }

instance H.ToMarkup EmailPage where
  toMarkup (EmailPage mprofile emails) =
    renderView' mprofile $ panelSentEmails emails


--------------------------------------------------------------------------------
-- | Display enqueued emails that are to the logged in user.
panelSentEmails :: [Email.Email] -> H.Html
panelSentEmails emails =
  panel' "Emails to be received" $ Misc.table titles display emails
 where
  titles = ["ID", "Template"]
  display Email.Email {..} =
    ( [Email.unEmailId _emailId, Email.emailTemplateName _emailTemplate]
    , []
    , Nothing
    )
