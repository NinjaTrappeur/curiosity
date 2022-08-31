{- |
Module: Curiosity.Html.Invoice
Description: Invoice pages (view and edit).
-}
module Curiosity.Html.Invoice
  ( InvoiceView(..)
  ) where

import qualified Curiosity.Data.Invoice        as Invoice
import           Curiosity.Html.Misc
import           Curiosity.Html.Navbar          ( navbar )
import qualified Smart.Html.Dsl                as Dsl
import qualified Smart.Html.Render             as Render
import           Smart.Html.Shared.Html.Icons   ( svgIconEdit )
import qualified Text.Blaze.Html5              as H
import           Text.Blaze.Html5               ( (!) )
import qualified Text.Blaze.Html5.Attributes   as A


--------------------------------------------------------------------------------
data InvoiceView = InvoiceView
  { _invoiceViewInvoice       :: Invoice.Invoice
  , _invoiceViewHasEditButton :: Bool
  }

instance H.ToMarkup InvoiceView where
  toMarkup (InvoiceView invoice hasEditButton) =
    renderView $ invoiceView invoice hasEditButton

invoiceView invoice hasEditButton =
  containerLarge $ H.div ! A.class_ "u-spacer-bottom-xl" $ do
    title' "Invoice" (Just "#")
    H.dl
      ! A.class_ "c-key-value c-key-value--horizontal c-key-value--short"
      $ do
          keyValuePair "ID" (Invoice._entityId invoice)
