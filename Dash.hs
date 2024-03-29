{-# LANGUAGE OverloadedStrings #-}

module Dash (
  MPD (..),
  Period (..),
  createMpd,
  createPeriod,
  toXml,
  renderMPD
) where

import qualified Data.ByteString.Lazy               as BL
import qualified Data.Text          as T
import qualified Data.Time.Clock    as UTC
import           Data.Time.Format
import           Text.XML.Generator


data MPD = MPD { mpdDisplay               :: Int
               , mpdAvailabilityStartTime :: T.Text
               , mpdPeriods               :: [Period]
               } deriving (Show)

data Period = Period { perId           :: Int,
                       perStart        :: Int,
                       perAdaptionSets :: [AdaptationSet]
                     } deriving (Show)

data AdaptationSet = AdaptationSet { asVideoFormat     :: VideoFormat
                                   , asRepresentations :: [Representation]
                                   } deriving (Show)

data VideoFormat = VideoFormat { vfMimeType :: T.Text
                               , vfCodecs   :: T.Text
                               } deriving (Show)

data Representation = Representation { repVideoProfile    :: VideoProfile
                                     , repSegmentTemplate :: SegmentTemplate
                                     } deriving (Show)

data VideoProfile = VideoProfile { vpId        :: T.Text,
                                   vpBandwith  :: Int,
                                   vpWidth     :: Int,
                                   vpHeight    :: Int,
                                   vpFrameRate :: Int
                                 } deriving (Show)

data SegmentTemplate = SegmentTemplate { stTimescale      :: Int,
                                         stDuration       :: Int,
                                         stStartNumber    :: Int,
                                         stMedia          :: T.Text,
                                         stInitialization :: T.Text
                                       } deriving (Show)

defaultVideoFormat :: VideoFormat
defaultVideoFormat = VideoFormat { vfMimeType = "video/mp4"
                                 , vfCodecs = "avc1.42c00d"
                                 }

videoProfile2160p :: VideoProfile
videoProfile2160p = VideoProfile { vpId = "2160p12Mbps"
                                , vpBandwith = 12000
                                , vpWidth = 4096
                                , vpHeight = 2160
                                , vpFrameRate = 24
                                }

videoProfile1080p :: VideoProfile
videoProfile1080p = VideoProfile { vpId = "1080p4800Kbps"
                                , vpBandwith = 4800
                                , vpWidth = 1920
                                , vpHeight = 1080
                                , vpFrameRate = 24
                                }

videoProfile720p :: VideoProfile
videoProfile720p = VideoProfile { vpId = "720p4800Kbps"
                                , vpBandwith = 2400
                                , vpWidth = 1280
                                , vpHeight = 720
                                , vpFrameRate = 24
                                }


type PeriodId = Int
type Iso8601Duration = T.Text
type SecDuration = Int

createMpd :: Int -> UTC.UTCTime -> [Period] -> MPD
createMpd display start = MPD display (T.pack $ formatUTC start)

createPeriod :: PeriodId -> SecDuration -> SecDuration -> T.Text -> Period
createPeriod pid startOffset duration folderName =
  Period pid startOffset [videoAdaptionSet]
    where videoAdaptionSet = AdaptationSet defaultVideoFormat [ representation2160p
                                                              , representation1080p
                                                              , representation720p ]
          representation2160p = Representation videoProfile2160p createSegmentTemplate
          representation1080p = Representation videoProfile1080p createSegmentTemplate
          representation720p = Representation videoProfile720p createSegmentTemplate
          createSegmentTemplate = SegmentTemplate
                                    24000
                                    duration
                                    0
                                    (T.concat [folderName, "/dash/segment_$Number$.m4s"])
                                    (T.concat [folderName, "/dash/init.mp4"])


showT :: (Show s) => s -> T.Text
showT = T.pack . show

formatUTC :: UTC.UTCTime -> String
formatUTC = formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"

class Iso8601 t where
  intervalDuration :: t -> Iso8601Duration

instance Iso8601 Int where
  intervalDuration t = T.pack $ "P" ++ show t ++ "S"


class XmlConvertible t where
  toXml :: t -> Xml Elem

instance XmlConvertible MPD where
  toXml m = xelem "MPD" $
                 xattr "xmlns:xsi" "http://www.w3.org/2001/XMLSchema-instance"
              <> xattr "xmlns" "urn:mpeg:dash:schema:mpd:2011"
              <> xattr "xsi:schemaLocation" "urn:mpeg:dash:schema:mpd:2011 http://standards.iso.org/ittf/PubliclyAvailableStandards/MPEG-DASH_schema_files/DASH-MPD.xsd"
              <> xattr "type" "dynamic"
              <> xattr "availabilityStartTime" (mpdAvailabilityStartTime m)
              <> xattr "timeShiftBufferDepth" "PT10M"
              <> xattr "minBufferTime" "PT10S"
              <> xattr "profiles" "urn:mpeg:dash:profile:isoff-live:2011"
              <> xattr "minimumUpdatePeriod" "PT2S"
              <#> map toXml (mpdPeriods m)

instance XmlConvertible Period where
  toXml p = xelem "Period" $
                  xattr "id" ((showT . perId) p)
              <>  xattr "start" ((intervalDuration . perStart) p)
              <#> map toXml (perAdaptionSets p)

instance XmlConvertible AdaptationSet where
  toXml as = xelem "AdaptationSet" $
                 xattr "mimeType" (vfMimeType $ asVideoFormat as)
              <> xattr "codecs" (vfCodecs $ asVideoFormat as)
             <#> map toXml (asRepresentations as)

instance XmlConvertible Representation where
  toXml r = xelem "Representation" $
                 xattr "id" (vpId $ repVideoProfile r)
              <> xattr "bandwidth" ((showT . vpBandwith . repVideoProfile) r)
              <> xattr "width" ((showT . vpWidth . repVideoProfile) r)
              <> xattr "height" ((showT . vpHeight . repVideoProfile) r)
              <> xattr "frameRate" ((showT . vpFrameRate . repVideoProfile) r)
             <#> toXml (repSegmentTemplate r)

instance XmlConvertible SegmentTemplate where
  toXml st = xelem "SegmentTemplate" $
                 xattr "timescale" ((showT . stTimescale) st)
              <> xattr "duration" ((showT . stDuration) st)
              <> xattr "startNumber" ((showT . stStartNumber) st)
              <> xattr "media" (stMedia st)
              <> xattr "initialization" (stInitialization st)

renderMPD :: MPD -> BL.ByteString
renderMPD = xrender . toXml
