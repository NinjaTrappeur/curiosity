{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{- |
Module: Curiosity.Data.Email
Description: Email -related data types.

This module contains data types used to represent emails. Within
"Curiosity.Data", they are used to record atomically that an email should be
sent during an STM operation. A separate thread should actually handle them.

-}
module Curiosity.Data.Email
  ( -- * Useful constants
    systemEmailAddr
    -- * Main data representation
  , Email(..)
  , EmailId(..)
  , emailIdPrefix
  , EmailTemplate(..)
  , emailTemplateName
  , Predicate(..)
  , applyPredicate
  , Err(..)
  ) where

import qualified Commence.Types.Wrapped        as W
import qualified Curiosity.Data.User           as User
import           Data.Aeson
import qualified Text.Blaze.Html5              as H
import           Web.FormUrlEncoded             ( FromForm(..)
                                                )

--------------------------------------------------------------------------------
systemEmailAddr :: User.UserEmailAddr
systemEmailAddr = "hello@smartcoop.sh"


--------------------------------------------------------------------------------
-- | This represents an email in database.
data Email = Email
  { _emailId        :: EmailId
  , _emailTemplate  :: EmailTemplate
  , _emailSender    :: User.UserEmailAddr
  , _emailRecipient :: User.UserEmailAddr
  }
  deriving (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Record ID of the form EMAIL-xxx.
newtype EmailId = EmailId { unEmailId :: Text }
               deriving (Eq, Show)
               deriving ( IsString
                        , FromJSON
                        , ToJSON
                        , H.ToMarkup
                        , H.ToValue
                        ) via Text
               deriving FromForm via W.Wrapped "email-id" Text

emailIdPrefix :: Text
emailIdPrefix = "EMAIL-"


--------------------------------------------------------------------------------
-- | All the emails that can be sent by the system are given by variants of the
-- `EmailTemplate` data type. They can be sent by the
-- `Curiosity.Core.createEmail` function. (TODO This should be a link to
-- "Curiosity.Runtime".)
data EmailTemplate =
    SignupConfirmationEmail
    -- ^ An email sent upon signup (see `Curiosity.Data.User.Signup`).
  | QuotationEmail
    -- ^ An email sent when a quotation form is successfully submitted to the
    -- system (see `Curiosity.Data.Quotation.SubmitQuotation`).
  | InvoiceEmail
  | InvoiceReminderEmail
  deriving (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

emailTemplateName :: EmailTemplate -> Text
emailTemplateName t = case t of
  SignupConfirmationEmail -> "SignupConfirmation"
  QuotationEmail -> "Quotation"
  InvoiceEmail -> "Invoice"
  InvoiceReminderEmail -> "InvoiceReminder"


--------------------------------------------------------------------------------
-- | Predicates to filter users.
data Predicate = AllEmails | EmailsFor User.UserEmailAddr
  deriving (Eq, Show)

applyPredicate :: Predicate -> Email -> Bool
applyPredicate AllEmails _ = True

applyPredicate (EmailsFor addr) Email {..} = addr == _emailRecipient


--------------------------------------------------------------------------------
data Err = Err
  { unErr :: Text
  }
  deriving (Eq, Exception, Show)
