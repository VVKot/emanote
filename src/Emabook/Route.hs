{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeApplications #-}

module Emabook.Route where

import Data.Aeson (ToJSON)
import Data.Data (Data)
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T
import Ema (Slug)
import qualified Ema
import Emabook.Route.Ext (Ext (..), Md)
import System.FilePath (splitExtension, splitPath)
import qualified Text.Show (Show (show))

-- | Represents the relative path to a source (.md) file under some directory.
--
-- This will also be our site route type.  That is, `Ema.routeUrl (r ::
-- Route)` gives us the URL to the generated HTML for this markdown file.
--
-- If you are using this repo as a template, you might want to use an ADT as
-- route (eg: data Route = Index | About)
newtype Route ext = Route {unRoute :: NonEmpty Slug}
  deriving (Eq, Ord, Data, Generic, ToJSON)

type MarkdownRoute = Route Md

instance Ext ext => Show (Route ext) where
  show (Route slugs) =
    toString $ "R[" <> toText (getExt (Proxy @ext)) <> "]:" <> T.intercalate "/" (toList $ fmap Ema.unSlug slugs)

-- | Represents the top-level index.md
indexRoute :: Route ext
indexRoute = Route $ "index" :| []

-- | Convert foo/bar.md to a @Route@
--
-- If the file is not a Markdown file, return Nothing.
mkRouteFromFilePath :: forall ext. Ext ext => FilePath -> Maybe (Route ext)
mkRouteFromFilePath fp = do
  let (base, ext) = splitExtension fp
  guard $ ext == getExt (Proxy @ext)
  let slugs = fromString . toString . T.dropWhileEnd (== '/') . toText <$> splitPath base
   in Route <$> nonEmpty slugs

routeSourcePath :: forall ext. Ext ext => Route ext -> FilePath
routeSourcePath r =
  if r == indexRoute
    then "index" <> getExt (Proxy @ext)
    else toString (T.intercalate "/" $ fmap Ema.unSlug $ toList $ unRoute r) <> ".md"

-- | Filename of the markdown file without extension
routeFileBase :: Route ext -> Text
routeFileBase =
  Ema.unSlug . head . NE.reverse . unRoute

-- | For use in breadcrumbs
routeInits :: Route ext -> NonEmpty (Route ext)
routeInits (Route ("index" :| [])) =
  one indexRoute
routeInits (Route (slug :| rest')) =
  indexRoute :| case nonEmpty rest' of
    Nothing ->
      one $ Route (one slug)
    Just rest ->
      Route (one slug) : go (one slug) rest
  where
    go :: NonEmpty Slug -> NonEmpty Slug -> [Route ext]
    go x (y :| ys') =
      let this = Route (x <> one y)
       in case nonEmpty ys' of
            Nothing ->
              one this
            Just ys ->
              this : go (unRoute this) ys

-- | Convert a route to URL slugs
encodeRoute :: Route ext -> [Slug]
encodeRoute = \case
  Route ("index" :| []) -> mempty
  Route paths -> toList paths

-- | Parse our route from URL slugs
--
-- For eg., /foo/bar maps to slugs ["foo", "bar"], which in our app gets
-- parsed as representing the route to /foo/bar.md.
decodeRoute :: [Slug] -> Maybe (Route ext)
decodeRoute = \case
  (nonEmpty -> Nothing) ->
    pure $ Route $ one "index"
  (nonEmpty -> Just slugs) -> do
    -- Heuristic to let requests to static files (eg: favicon.ico) to pass through
    guard $ not (any (T.isInfixOf "." . Ema.unSlug) slugs)
    pure $ Route slugs