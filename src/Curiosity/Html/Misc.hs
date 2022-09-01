{- |
Module: Curiosity.Html.Misc
Description: Helper functions to build HTML views.

TODO Move to smart-design-hs Misc.
-}
module Curiosity.Html.Misc
  ( containerMedium
  , containerLarge
  , keyValuePair
  , fullScroll

  -- Form
  , title
  , title'
  , inputText
  , submitButton

  -- View
  , editButton

  -- Keep here:
  , renderView
  , renderForm
  ) where

import qualified Curiosity.Data.User           as User
import           Curiosity.Html.Navbar          ( navbar )
import qualified Smart.Html.Dsl                as Dsl
import qualified Smart.Html.Render             as Render
import           Smart.Html.Shared.Html.Icons   ( svgIconEdit )
import qualified Text.Blaze.Html5              as H
import           Text.Blaze.Html5               ( (!)
                                                , Html
                                                )
import qualified Text.Blaze.Html5.Attributes   as A


--------------------------------------------------------------------------------
-- | This works well paired with a side menu.
-- TODO Probably move this directly to a "layout" function such as
-- withSideMenuFullScroll.
containerMedium content =
  H.div
    ! A.class_ "u-scroll-wrapper-body"
    $ H.div
    ! A.class_ "o-container o-container--large"
    $ H.div
    ! A.class_ "o-container-vertical"
    $ H.div
    ! A.class_ "o-container o-container--medium"
    $ content

-- | This works well when not paired with a side menu.
-- TODO Probably move this directly to a "layout" function such as fullScroll.
containerLarge content =
  H.div
    ! A.class_ "u-scroll-wrapper-body"
    $ H.div
    ! A.class_ "o-container o-container--large"
    $ H.div
    ! A.class_ "o-container-vertical"
    $ H.div
    ! A.class_ "u-spacer-bottom-xl"
    $ content

keyValuePair :: H.ToMarkup a => Text -> a -> H.Html
keyValuePair key value = H.div ! A.class_ "c-key-value-item" $ do
  H.dt ! A.class_ "c-key-value-item__key" $ H.toHtml key
  H.dd ! A.class_ "c-key-value-item__value" $ H.toHtml value

-- | The corresponding layout with a side menu is withSideMenuFullScroll.
-- TODO Move to Smart.Html.Layout.
fullScroll content = H.main ! A.class_ "u-maximize-width" $ do
  content

renderView content =
  Render.renderCanvasFullScroll
    . Dsl.SingletonCanvas
    $ H.div
    ! A.class_ "c-app-layout u-scroll-vertical"
    $ do
        H.header $ H.toMarkup . navbar $ "TODO username"
        fullScroll content

renderForm :: User.UserProfile -> Text -> Html -> Html
renderForm profile s content =
  Render.renderCanvasFullScroll
    . Dsl.SingletonCanvas
    $ H.div
    ! A.class_ "c-app-layout u-scroll-vertical"
    $ do
        H.header
          $ H.toMarkup
          . navbar
          . User.unUserName
          . User._userCredsName
          $ User._userProfileCreds profile
        H.main ! A.class_ "u-maximize-width" $ containerMedium $ do
          title s
          H.div
            ! A.class_ "o-form-group-layout o-form-group-layout--horizontal"
            $ H.form content


--------------------------------------------------------------------------------
title :: Text -> Html
title s = title' s Nothing

title' :: Text -> Maybe H.AttributeValue -> Html
title' s mEditButton =
  H.div
    ! A.class_ "u-spacer-bottom-l"
    $ H.div
    ! A.class_ "c-navbar c-navbar--unpadded c-navbar--bordered-bottom"
    $ H.div
    ! A.class_ "c-toolbar"
    $ do
        H.div
          ! A.class_ "c-toolbar__left"
          $ H.h3
          ! A.class_ "c-h3 u-m-b-0"
          $ H.text s
        maybe mempty editButton mEditButton

inputText
  :: Text -> H.AttributeValue -> Maybe H.AttributeValue -> Maybe Text -> Html
inputText label name mvalue mhelp = H.div ! A.class_ "o-form-group" $ do
  H.label ! A.class_ "o-form-group__label" ! A.for name $ H.toHtml label
  H.div
    ! A.class_ "o-form-group__controls o-form-group__controls--full-width"
    $ do
        maybe identity (\value -> (! (A.value value))) mvalue
          $ H.input
          ! A.class_ "c-input"
          ! A.id name
          ! A.name name
        maybe mempty ((H.p ! A.class_ "c-form-help-text") . H.text) mhelp

submitButton :: H.AttributeValue -> Html -> Html
submitButton submitUrl label =
  H.div
    ! A.class_ "o-form-group"
    $ H.div
    ! A.class_ "u-spacer-left-auto"
    $ H.button
    ! A.class_ "c-button c-button--primary"
    ! A.formaction (H.toValue submitUrl)
    ! A.formmethod "POST"
    $ H.span
    ! A.class_ "c-button__content"
    $ H.span
    ! A.class_ "c-button__label"
    $ label

--------------------------------------------------------------------------------
editButton :: H.AttributeValue -> Html
editButton lnk =
  H.div
    ! A.class_ "c-toolbar__right"
    $ H.a
    ! A.class_ "c-button c-button--secondary"
    ! A.href lnk
    $ H.span
    ! A.class_ "c-button__content"
    $ do
        H.div ! A.class_ "o-svg-icon o-svg-icon-edit" $ H.toHtml svgIconEdit
        H.span ! A.class_ "c-button__label" $ "Edit"
