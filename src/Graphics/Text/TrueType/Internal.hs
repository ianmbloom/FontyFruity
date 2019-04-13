-- | This module provide internal access to many structure,
-- not exported by default. The stability of this module is
-- absolutely not insured.
module Graphics.Text.TrueType.Internal
    ( Font( .. )
    , fontOffsetTable
    , fontTables
    , fontNames
    , fontHeader
    , fontMaxp
    , fontMap
    , fontGlyph
    , fontLoca
    , fontHorizontalHeader
    , fontHorizontalMetrics
    , FontHeader( .. )
    , HeaderFlags( .. )
    , HorizontalHeader( .. )
    , hheaAscent
    , hheaDescent
    , hheaLineGap
    , hheaAdvanceWidthMax
    , hheaMinLeftSideBearing
    , hheaMinRightSideBearing
    , hheaXmaxExtent
    , hheaCaretSlopeRise
    , hheaCaretSlopeRun
    , hheaCaretOffset
    , hheaMetricDataFormat
    , hheaLongHorMetricCount
    , HorizontalMetric( .. )
    , HorizontalMetricsTable( .. )
    , MaxpTable( .. )
    , FWord( .. )
    , Fixed( .. )
    ) where

import Graphics.Text.TrueType.MaxpTable
import Graphics.Text.TrueType.HorizontalInfo
import Graphics.Text.TrueType.FontType
import Graphics.Text.TrueType.Header
import Graphics.Text.TrueType.Types
