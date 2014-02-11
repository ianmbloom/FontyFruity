{-# LANGUAGE TupleSections #-}
{-# LANGUAGE OverloadedStrings #-}
module Graphics.Text.TrueType
     where

import Control.Applicative( (<$>)
                          {-, (<*>)-}
                          )
import Control.Monad( foldM )
{-import Data.Bits( setBit, testBit )-}
import Data.Function( on )
{-import Data.Int( Int16 )-}
import Data.List( sortBy
                {-, foldl'-}
                )
import Data.Word(
                  {-Word8-}
                {-, Word16-}
                 Word32
                {-, Word64-}
                )
import Data.Binary( Binary( .. ), decode )
import Data.Binary.Get( Get
                      , bytesRead
                      {-, getWord8-}
                      , getWord16be
                      , getWord32be
                      {-, getWord64be-}
                      , getByteString
                      , getLazyByteString
                      , skip
                      )


{-import Data.Binary.Put( putWord8-}
                      {-, putWord16be-}
                      {-, putWord32be-}
                      {-, putByteString-}
                      {-)-}

{-import Data.Monoid( mempty )-}

import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as LB
{-import qualified Data.ByteString.Char8 as BC-}
import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as VU

{-import Graphics.Text.TrueType.Types-}
import Graphics.Text.TrueType.MaxpTable
import Graphics.Text.TrueType.Glyph
import Graphics.Text.TrueType.Header
import Graphics.Text.TrueType.OffsetTable
import Graphics.Text.TrueType.CharacterMap

data Font = Font
    { _fontOffsetTable :: !OffsetTable
    , _fontTables      :: ![(B.ByteString, B.ByteString)]
    , _fontHeader      :: Maybe FontHeader
    , _fontMaxp        :: Maybe MaxpTable
    , _fontGlyph       :: Maybe (V.Vector Glyph)
    , _fontLoca        :: Maybe (VU.Vector Word32)
    }
    deriving (Eq, Show)

emptyFont :: OffsetTable -> Font
emptyFont table = Font
    { _fontTables      = []
    , _fontOffsetTable = table
    , _fontHeader      = Nothing
    , _fontGlyph       = Nothing
    , _fontMaxp        = Nothing
    , _fontLoca        = Nothing
    }

fetchTables :: OffsetTable -> Get Font
fetchTables tables = foldM fetch (emptyFont tables) tableList
  where
    tableList = sortBy (compare `on` _tdeOffset)
                    . V.toList
                    $ _otEntries tables
    gotoOffset entry = do
        readed <- bytesRead 
        let toDrop = fromIntegral (_tdeOffset entry) - readed
        if toDrop < 0 then fail "Weirdo weird"
        else skip $ fromIntegral toDrop

    getLoca font@(Font { _fontMaxp = Just maxp, _fontHeader = Just hdr })
      | _fHdrIndexToLocFormat hdr == 0 = do
          v <- VU.replicateM glyphCount (fromIntegral <$> getWord16be)
          return $ font { _fontLoca = Just v }
      | otherwise = do
          v <- VU.replicateM glyphCount getWord32be
          return $ font { _fontLoca = Just v }
      where glyphCount = fromIntegral $ _maxpnumGlyphs maxp
    getLoca font = return font

    getGlyph font@(Font { _fontLoca = Just locations }) str =
      return $ font { _fontGlyph = Just . V.map decoder $ VU.convert locations }
          where decoder = decode . (`LB.drop` str) . fromIntegral
    getGlyph font _ = return font

    fetch font entry | _tdeTag entry == "loca" =
      gotoOffset entry >> getLoca font

    fetch font entry | _tdeTag entry == "glyf" =
      gotoOffset entry >>
          getLazyByteString (fromIntegral $ _tdeLength entry) >>= getGlyph font

    fetch font entry | _tdeTag entry == "head" = do
      table <- gotoOffset entry >> get
      return $ font { _fontHeader = Just table }

    fetch font entry | _tdeTag entry == "maxp" = do
      table <- gotoOffset entry >> get
      return $ font { _fontMaxp = Just table }

    fetch font entry = do
      let tableLength = fromIntegral $ _tdeLength entry
      rawData <- gotoOffset entry >> getByteString tableLength
      return $ font { _fontTables =
                        (_tdeTag entry, rawData) : _fontTables font}

instance Binary Font where
  put _ = error "Binary.put Font - unimplemented"
  get = get >>= fetchTables

type Dpi = Int
type PointSize = Int

getGlyphIndexCurvesAtPointSize :: Font -> Dpi -> PointSize -> Int
                               -> [VU.Vector (Float, Float)]
getGlyphIndexCurvesAtPointSize Font { _fontHeader = Nothing } _ _ _ = []
getGlyphIndexCurvesAtPointSize Font { _fontGlyph = Nothing } _ _ _ = []
getGlyphIndexCurvesAtPointSize
    Font { _fontHeader = Just hdr, _fontGlyph = Just glyph } dpi pointSize index
        | index >= V.length glyph = []
        | otherwise = glyphExtract $ glyph V.! index
  where
    pixelSize = fromIntegral (pointSize * dpi) / 72
    emSize = fromIntegral $ _fUnitsPerEm hdr

    toPixelCoordinate coord =
        (fromIntegral coord * pixelSize) / emSize

    glyphExtract Glyph { _glyphContent = GlyphComposite _ _ } = []
    glyphExtract Glyph { _glyphContent = GlyphSimple countour } =
        [ VU.map (\(x, y) -> (toPixelCoordinate x, toPixelCoordinate y)) c
                | c <- _glyphPoints countour]

