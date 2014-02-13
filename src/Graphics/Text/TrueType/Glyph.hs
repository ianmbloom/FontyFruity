{-# LANGUAGE TupleSections #-}
module Graphics.Text.TrueType.Glyph
    ( GlyphHeader( .. )
    , GlyphContour( .. )
    , CompositeScaling( .. )
    , GlyphComposition( .. )
    , GlyphContent( .. )
    , Glyph( .. )
    , GlyphFlag( .. )
    ) where

import Control.Applicative( (<$>), (<*>) )
import Data.Bits( setBit, testBit, shiftL )
import Data.Int( Int16 )
import Data.List( mapAccumR )
import Data.Monoid( mempty )
import Data.Word( Word8, Word16 )
import Data.Binary( Binary( .. ) )
import Data.Binary.Get( Get
                      , getWord8
                      , getWord16be )

import Data.Binary.Put( putWord8, putWord16be )

import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as VU

import Text.Printf
import Debug.Trace

data GlyphHeader = GlyphHeader
    { -- | If the number of contours is greater than or equal
      -- to zero, this is a single glyph; if negative, this is
      -- a composite glyph.
      _glfNumberOfContours :: !Int16
      -- | Minimum x for coordinate data.
    , _glfXMin             :: !Int16
      -- | Minimum y for coordinate data.
    , _glfYMin             :: !Int16
      -- | Maximum x for coordinate data.
    , _glfXMax             :: !Int16
      -- | Maximum y for coordinate data.
    , _glfYMax             :: !Int16
    }
    deriving (Eq, Show)

instance Binary GlyphHeader where
    get = GlyphHeader <$> g16 <*> g16 <*> g16 <*> g16 <*> g16
      where g16 = fromIntegral <$> getWord16be

    put (GlyphHeader count xmini ymini xmaxi ymaxi) =
        p16 count >> p16 xmini >> p16 ymini >> p16 xmaxi >> p16 ymaxi
      where p16 = putWord16be . fromIntegral

data GlyphContour = GlyphContour
    { _glyphInstructions :: !(VU.Vector Word8)
    , _glyphPoints       :: ![VU.Vector (Int16, Int16)]
    }
    deriving (Eq, Show)

data CompositeScaling = CompositeScaling
    { _a :: !Int16
    , _b :: !Int16
    , _c :: !Int16
    , _d :: !Int16
    , _e :: !Int16
    , _f :: !Int16
    }
    deriving (Eq, Show)

data GlyphComposition = GlyphComposition
    { _glyphCompositeFlag    :: !Word16
    , _glyphCompositeIndex   :: !Word16
    , _glyphCompositionArg   :: !(Int16, Int16)
    , _glyphCompositionScale :: !CompositeScaling
    }
    deriving (Eq, Show)

data GlyphContent
    = GlyphSimple    GlyphContour
    | GlyphComposite (V.Vector GlyphComposition) (VU.Vector Word8)
    deriving (Eq, Show)

data Glyph = Glyph
    { _glyphHeader  :: !GlyphHeader
    , _glyphContent :: !GlyphContent
    }
    deriving (Eq, Show)

getCompositeOutline :: Get GlyphContent
getCompositeOutline =
    (\(instr, vals) -> GlyphComposite (V.fromList vals) instr) <$> go
  where
    go = do
      flag <- getWord16be
      index <- getWord16be
      args <- fetchArguments flag
      scaling <- fetchScaling flag
      let fullScaling = fetchOffset scaling args flag
          value = GlyphComposition flag index args fullScaling

      if flag `testBit` mORE_COMPONENTS then
          (\(instr, acc) -> (instr, value : acc )) <$> go
      else
        if flag `testBit` wE_HAVE_INSTRUCTIONS then do
            count <- fromIntegral <$> getWord16be
            (, [value]) <$> VU.replicateM count getWord8
        else
            return (mempty, [value])


    fetchArguments flag
        | flag `testBit` aRG_1_AND_2_ARE_WORDS =
            (,) <$> getInt16be <*> getInt16be
        | otherwise =
            (,) <$> getInt8 <*> getInt8

    fetchScaling flag
        | flag `testBit` wE_HAVE_A_SCALE =
            (\v -> CompositeScaling v 0 0 v) <$> getF2Dot14
        | flag `testBit` wE_HAVE_AN_X_AND_Y_SCALE =
            (\x y -> CompositeScaling x 0 0 y) <$> getF2Dot14 <*> getF2Dot14
        | flag `testBit` wE_HAVE_A_TWO_BY_TWO =
            CompositeScaling <$> getF2Dot14 <*> getF2Dot14
                             <*> getF2Dot14 <*> getF2Dot14
        | otherwise = return $ CompositeScaling one 0 0 one
           where one = 1 `shiftL` 14

    fetchOffset scaling (a1, a2) flag
        | flag `testBit` aRGS_ARE_XY_VALUES = scaling a1 a2
        | otherwise = scaling 0 0 -- TODO fix this crap

    {--
    if (!ARGS_ARE_XY_VALUES)
        1st short contains the index of matching point in compound being constructed
        2nd short contains index of matching point in component -}

    getInt16be = fromIntegral <$> getWord16be
    getF2Dot14 = fromIntegral <$> getWord16be
    getInt8 = fromIntegral <$> getWord8

    aRG_1_AND_2_ARE_WORDS  = 0
    aRGS_ARE_XY_VALUES  = 1
    {-rOUND_XY_TO_GRID  = 2-}
    wE_HAVE_A_SCALE  = 3
    {-rESERVED  = 4-}
    mORE_COMPONENTS  = 5
    wE_HAVE_AN_X_AND_Y_SCALE  = 6
    wE_HAVE_A_TWO_BY_TWO  = 7
    wE_HAVE_INSTRUCTIONS  = 8
    {-uSE_MY_METRICS  = 9-}
    {-oVERLAP_COMPOUND  = 10-}
    {-sCALED_COMPONENT_OFFSET  = 11-}
    {-uNSCALED_COMPONENT_OFFSET = 12-}

data GlyphFlag = GlyphFlag
    { -- | If set, the point is on the curve;
      -- otherwise, it is off the curve.
      _flagOnCurve :: !Bool
      -- | If set, the corresponding x-coordinate is 1
      -- byte long. If not set, 2 bytes.
    , _flagXshort  :: !Bool
      -- | If set, the corresponding y-coordinate is 1
      -- byte long. If not set, 2 bytes.
    , _flagYShort  :: !Bool
      -- | If set, the next byte specifies the number of additional
      -- times this set of flags is to be repeated. In this way, the
      -- number of flags listed can be smaller than the number of
      -- points in a character.
    , _flagRepeat  :: !Bool
      -- | This flag has two meanings, depending on how the x-Short
      -- Vector flag is set. If x-Short Vector is set, this bit
      -- describes the sign of the value, with 1 equalling positive and
      -- 0 negative. If the x-Short Vector bit is not set and this bit is set,
      -- then the current x-coordinate is the same as the previous x-coordinate.
      -- If the x-Short Vector bit is not set and this bit is also not set, the
      -- current x-coordinate is a signed 16-bit delta vector.
    , _flagXSame   :: !Bool
      -- | This flag has two meanings, depending on how the y-Short Vector flag
      -- is set. If y-Short Vector is set, this bit describes the sign of the
      -- value, with 1 equalling positive and 0 negative. If the y-Short Vector
      -- bit is not set and this bit is set, then the current y-coordinate is the
      -- same as the previous y-coordinate. If the y-Short Vector bit is not set
      -- and this bit is also not set, the current y-coordinate is a signed
      -- 16-bit delta vector.
    , _flagYSame   :: !Bool
    }
    deriving (Eq, Show)

instance Binary GlyphFlag where
    put (GlyphFlag a0 a1 a2 a3 a4 a5) =
        putWord8 . foldl setter 0 $ zip [0..] [a0, a1, a2, a3, a4, a5]
      where setter v ( _, False) = v
            setter v (ix, True) = setBit v ix
    get = do
      tester <- testBit <$> getWord8
      return $ GlyphFlag
        { _flagOnCurve = tester 0
        , _flagXshort  = tester 1
        , _flagYShort  = tester 2
        , _flagRepeat  = tester 3
        , _flagXSame   = tester 4
        , _flagYSame   = tester 5
        }

getGlyphFlags :: Int -> Get [GlyphFlag]
getGlyphFlags count = go 0
  where
    go n | n >= count = return []
    go n = do
      flag <- get
      if _flagRepeat flag
        then do
          repeatCount <- fromIntegral <$> getWord8
          let real = min (count - n) (repeatCount + 1)
          (replicate real flag ++) <$> go (n + real)
        else (flag :) <$> go (n + 1)

getCoords :: [GlyphFlag] -> Get (VU.Vector (Int16, Int16))
getCoords flags = trace (show flags) $
    VU.fromList <$> (zip <$> go (_flagXSame, _flagXshort) 0 flags
                         <*> go (_flagYSame, _flagYShort) 0 flags)
  where
    go _ _ [] = return []
    go axx@(isSame, isShort) prevCoord (flag:flagRest) = do
        let fetcher
              | isShort flag && isSame flag =
                  (prevCoord +) . fromIntegral <$> getWord8
              | isShort flag = 
                  (prevCoord - ) . fromIntegral <$> getWord8
              | isSame flag =
                  return prevCoord
              | otherwise =
                  (prevCoord +) . fromIntegral <$> getWord16be

        newCoord <- fetcher
        (newCoord :) <$> go axx newCoord flagRest

getSimpleOutline :: Int16 -> Get GlyphContent
getSimpleOutline counterCount = do
    endOfPoints <- VU.replicateM (fromIntegral counterCount) getWord16be
    let pointCount = VU.last endOfPoints + 1
    instructionCount <- fromIntegral <$> getWord16be
    instructions <- VU.replicateM instructionCount getWord8

    flags <- getGlyphFlags $ fromIntegral pointCount
    GlyphSimple . GlyphContour instructions 
                . breakOutline endOfPoints <$> getCoords flags
  where
    prepender (v, lst) = v : lst
    breakOutline endPoints coords =
        prepender . mapAccumR breaker coords . VU.toList $ VU.init endPoints
          where breaker array ix = VU.splitAt (fromIntegral ix + 1) array

instance Binary Glyph where
    put _ = fail "Glyph.put - unimplemented"
    get = do
      hdr <- get
      case _glfNumberOfContours hdr of
        -1 -> Glyph hdr <$> getCompositeOutline
        n -> Glyph hdr <$> getSimpleOutline n

