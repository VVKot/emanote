{-# LANGUAGE RecordWildCards #-}

module Emanote.Pandoc.Renderer.Embed where

import Control.Lens.Operators ((^.))
import Data.Map.Syntax ((##))
import qualified Data.Text as T
import qualified Ema.CLI
import Emanote.Model (Model)
import qualified Emanote.Model.Link.Rel as Rel
import qualified Emanote.Model.Note as MN
import qualified Emanote.Model.StaticFile as SF
import qualified Emanote.Model.Title as Tit
import Emanote.Pandoc.BuiltinFilters (preparePandoc)
import qualified Emanote.Pandoc.Markdown.Syntax.WikiLink as WL
import Emanote.Pandoc.Renderer (NoteRenderers, PandocBlockRenderer, noteSpliceWith)
import qualified Emanote.Pandoc.Renderer.Url as Url
import qualified Emanote.Route as R
import qualified Emanote.Route.SiteRoute as SR
import qualified Heist.Extra as HE
import qualified Heist.Extra.Splices.Pandoc as HP
import Heist.Extra.Splices.Pandoc.Ctx (RenderCtx (..), ctxSansCustomSplicing)
import qualified Heist.Interpreted as HI
import qualified Text.Pandoc.Definition as B

embedWikiLinkResolvingSplice ::
  Monad n => PandocBlockRenderer n x
embedWikiLinkResolvingSplice emaAction model nf (ctxSansCustomSplicing -> ctx) _ blk =
  case blk of
    B.Para [B.Link (_id, _class, otherAttrs) _is (url, tit)] -> do
      Rel.URTWikiLink (WL.WikiLinkEmbed, wl) <-
        Rel.parseUnresolvedRelTarget (otherAttrs <> one ("title", tit)) url
      case Url.resolveWikiLinkMustExist model wl of
        Left err ->
          pure $ brokenLinkDivWrapper err blk
        Right res -> do
          embedSiteRoute emaAction model nf ctx wl res
    _ ->
      Nothing
  where
    brokenLinkDivWrapper err block =
      HP.rpBlock ctx $
        B.Div (Url.brokenLinkAttr err) $
          one block

embedSiteRoute :: Monad n => Ema.CLI.Action -> Model -> NoteRenderers n -> HP.RenderCtx n -> WL.WikiLink -> Either MN.Note SF.StaticFile -> Maybe (HI.Splice n)
embedSiteRoute emaAction model nf RenderCtx {..} wl = \case
  Left note -> do
    pure . runEmbedTemplate "note" $ do
      "ema:note:title" ## Tit.titleSplice (preparePandoc model) (MN._noteTitle note)
      "ema:note:url" ## HI.textSplice (SR.siteRouteUrl model $ SR.lmlSiteRoute $ note ^. MN.noteRoute)
      "ema:note:pandoc"
        ## noteSpliceWith nf classMap emaAction model note
  Right staticFile -> do
    let r = staticFile ^. SF.staticFileRoute
        fp = staticFile ^. SF.staticFilePath
    if
        | any (`T.isSuffixOf` toText fp) imageExts ->
          pure . runEmbedTemplate "image" $ do
            "ema:url" ## HI.textSplice (toText $ R.encodeRoute r)
            "ema:alt" ## HI.textSplice $ show wl
        | any (`T.isSuffixOf` toText fp) videoExts -> do
          pure . runEmbedTemplate "video" $ do
            "ema:url" ## HI.textSplice (toText $ R.encodeRoute r)
        | otherwise -> Nothing
  where
    runEmbedTemplate name splices = do
      tpl <- HE.lookupHtmlTemplateMust $ "/templates/filters/embed-" <> name
      HE.runCustomTemplate tpl splices

imageExts :: [Text]
imageExts =
  [ ".jpg",
    ".jpeg",
    ".png",
    ".svg",
    ".gif",
    ".bmp"
  ]

videoExts :: [Text]
videoExts =
  [ ".mp4",
    ".webm",
    ".ogv"
  ]