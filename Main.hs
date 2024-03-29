{-# LANGUAGE OverloadedStrings #-}

import           Data.Maybe
import qualified Data.Text                          as T
import qualified Data.Time.Clock                    as UTC

import           Database.MySQL.Simple
import           Database.MySQL.Simple.QueryResults
import           Database.MySQL.Simple.Result

import           Dash

import qualified Data.ByteString.Lazy               as BL

import Control.Arrow
import Control.Concurrent ( threadDelay )
import Control.Monad

import qualified Text.Show.Pretty as Pr
import Criterion.Main

data Display = Display { dId :: Int } deriving (Show)

data CampaignInfo = CampaignInfo { cid      :: Int,
                                   display  :: Int,
                                   start    :: UTC.UTCTime,
                                   end      :: UTC.UTCTime,
                                   src      :: T.Text,
                                   mpd      :: Maybe T.Text,
                                   duration :: Int
                                 } deriving (Show)

instance QueryResults Display where
    convertResults [fa] [va] = Display dId
        where dId = convert fa va
    convertResults fs vs  = convertError fs vs 1

instance QueryResults CampaignInfo where
    convertResults [fa,fb,fc,fd,fe,ff,fg] [va,vb,vc,vd,ve,vf,vg] =
            CampaignInfo cid display start end src mpd duration
        where cid = convert fa va
              display = convert fb vb
              start = convert fc vc
              end = convert fd vd
              src = convert fe ve
              mpd = convert ff vf
              duration = convert fg vg
    convertResults fs vs  = convertError fs vs 7


getDisplays :: Connection -> IO [Display]
getDisplays conn = query_ conn "select id from display"

findCampaignInfo :: Connection -> IO [CampaignInfo]
findCampaignInfo conn = query_ conn
        "select c.id, c.display_id, c.start, c.end, m.src, m.mpd_url, m.duration from campaign c left join media m on m.id = c.media_id where c.start >= now()"

filterOnlyFirstN = take 10

filterNoMpd = filter (isJust . mpd)

--filterStartEnd cis now = filter (\ci -> (start ci >= now) && (end ci <= now)) cis

filterCampaignInfos :: [CampaignInfo] -> [CampaignInfo]
filterCampaignInfos = filterNoMpd  . filterOnlyFirstN

filterByDisplay :: [CampaignInfo] -> Display -> [CampaignInfo]
filterByDisplay cis d = filter (\ci -> display ci == dId d) cis

createPeriods :: [CampaignInfo] -> [Period]
createPeriods = createPeriods' []

createPeriods' :: [Period] -> [CampaignInfo] -> [Period]
createPeriods' [] [] = []
createPeriods' ps [] = ps
createPeriods' [] (x:xs) = createPeriods' [newPeriod] xs
                          where newPeriod = createPeriod 0 0 (duration x) folderName
                                folderName = src x -- TODO: concept
createPeriods' ps (x:xs) = createPeriods' (newPeriod : ps) xs
                          where newPeriod = createPeriod (length ps) accStartOffset (duration x) folderName
                                accStartOffset = duration x + perStart (last ps)
                                folderName = src x -- TODO: concept


getMpds :: IO [MPD]
getMpds = do
  now  <- UTC.getCurrentTime
  conn <- connect defaultConnectInfo { connectPassword = "password", connectDatabase = "plads" }

  displays <- getDisplays conn
  campaignInfos <- findCampaignInfo conn
  --print $ "number of displays: " ++ show (length displays)
  --print $ "number of campaigninfos: " ++ show (length campaignInfos)
  let periodsOfDisplays = filter (not . null . fst) $ map ( createPeriods
                                                            . filterCampaignInfos
                                                            . filterByDisplay campaignInfos
                                                            &&&
                                                            dId ) displays

  --print $ "number of displays with periods: " ++ show (length periodsOfDisplays)
  let mpds = map (\(periods, display) -> createMpd display now periods) periodsOfDisplays
  --print $ "number of first display's periods: " ++ show (length $ mpdPeriods $ head mpds)
  --putStrLn $ Pr.ppShow mpds

  return mpds



updateStream :: MPD -> IO ()
updateStream mpd = do
  print $ mpdDisplay mpd
  BL.writeFile (show (mpdDisplay mpd) ++ ".xml") (renderMPD mpd)

main :: IO ()
main = do
  --defaultMain [ bgroup "mpd xml" [ bench "1x" $ whnfIO xml ] ]
  forever $ do
    mpds <- getMpds
    mapM_ updateStream mpds
    threadDelay 1000000


-- INITIAL CONCEPT:
-- getCampaigns monitor         -- Monitor -> [Campaign]
--  . filterCampaign           -- [Campaign] -> [Campaign]
--    . map createPeriod         -- Campaign -> [Period]
--      . createMpd monitor      -- [Period] -> Mpd
--        . updateStream         -- Mpd -> IO
