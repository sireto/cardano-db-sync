{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Cardano.Sync.Api
  ( SyncEnv (..)
  , LedgerEnv (..)
  , SyncDataLayer (..)
  , mkSyncEnvFromConfig
  , verifyFilePoints
  , getLatestPoints
  ) where

import           Cardano.Prelude (Proxy (..), catMaybes, find)

import           Cardano.BM.Trace (Trace)

import qualified Cardano.Ledger.BaseTypes as Ledger

import           Cardano.Sync.Config.Cardano
import           Cardano.Sync.Config.Shelley
import           Cardano.Sync.Config.Types
import           Cardano.Sync.Error
import           Cardano.Sync.LedgerState
import           Cardano.Sync.Types
import           Cardano.Sync.Util (textShow)

import           Cardano.Slotting.Slot (SlotNo (..))

import qualified Cardano.Chain.Genesis as Byron
import           Cardano.Crypto.ProtocolMagic

import           Data.ByteString (ByteString)
import           Data.Text (Text)

import           Ouroboros.Consensus.Block.Abstract (HeaderHash, fromRawHash)
import           Ouroboros.Consensus.BlockchainTime.WallClock.Types (SystemStart (..))
import           Ouroboros.Consensus.Node.ProtocolInfo (ProtocolInfo)
import           Ouroboros.Network.Block (Point (..))
import           Ouroboros.Network.Magic (NetworkMagic (..))
import qualified Ouroboros.Network.Point as Point

import qualified Shelley.Spec.Ledger.Genesis as Shelley

data SyncEnv = SyncEnv
  { envProtocol :: !SyncProtocol
  , envNetworkMagic :: !NetworkMagic
  , envSystemStart :: !SystemStart
  , envDataLayer :: !SyncDataLayer
  , envLedger :: !LedgerEnv
  }

-- The base @DataLayer@ that contains the functions required for syncing to work.
data SyncDataLayer = SyncDataLayer
  { sdlGetSlotHash :: SlotNo -> IO [(SlotNo, ByteString)]
  , sdlGetLatestBlock :: IO (Maybe Block)
  , sdlGetLatestSlotNo :: IO SlotNo
  }

mkSyncEnv
    :: SyncDataLayer -> Trace IO Text -> ProtocolInfo IO CardanoBlock -> Ledger.Network
    -> NetworkMagic -> SystemStart -> LedgerStateDir -> EpochSlot
    -> IO SyncEnv
mkSyncEnv dataLayer trce protoInfo nw nwMagic systemStart dir stableEpochSlot = do
  ledgerEnv <- mkLedgerEnv trce protoInfo dir nw stableEpochSlot
  pure $ SyncEnv
          { envProtocol = SyncProtocolCardano
          , envNetworkMagic = nwMagic
          , envSystemStart = systemStart
          , envDataLayer = dataLayer
          , envLedger = ledgerEnv
          }

mkSyncEnvFromConfig :: SyncDataLayer -> Trace IO Text -> LedgerStateDir -> GenesisConfig -> IO (Either SyncNodeError SyncEnv)
mkSyncEnvFromConfig trce dataLayer dir genCfg =
    case genCfg of
      GenesisCardano _ bCfg sCfg _aCfg
        | unProtocolMagicId (Byron.configProtocolMagicId bCfg) /= Shelley.sgNetworkMagic (scConfig sCfg) ->
            pure . Left . NECardanoConfig $
              mconcat
                [ "ProtocolMagicId ", textShow (unProtocolMagicId $ Byron.configProtocolMagicId bCfg)
                , " /= ", textShow (Shelley.sgNetworkMagic $ scConfig sCfg)
                ]
        | Byron.gdStartTime (Byron.configGenesisData bCfg) /= Shelley.sgSystemStart (scConfig sCfg) ->
            pure . Left . NECardanoConfig $
              mconcat
                [ "SystemStart ", textShow (Byron.gdStartTime $ Byron.configGenesisData bCfg)
                , " /= ", textShow (Shelley.sgSystemStart $ scConfig sCfg)
                ]
        | otherwise ->
            Right <$> mkSyncEnv trce dataLayer (mkProtocolInfoCardano genCfg) (Shelley.sgNetworkId $ scConfig sCfg)
                        (NetworkMagic . unProtocolMagicId $ Byron.configProtocolMagicId bCfg)
                        (SystemStart .Byron.gdStartTime $ Byron.configGenesisData bCfg)
                        dir (calculateStableEpochSlot $ scConfig sCfg)


getLatestPoints :: SyncEnv -> IO [CardanoPoint]
getLatestPoints env = do
    files <- listLedgerStateFilesOrdered $ leDir (envLedger env)
    verifyFilePoints env files

verifyFilePoints :: SyncEnv -> [LedgerStateFile] -> IO [CardanoPoint]
verifyFilePoints env files =
    catMaybes <$> mapM validLedgerFileToPoint files
  where
    validLedgerFileToPoint :: LedgerStateFile -> IO (Maybe CardanoPoint)
    validLedgerFileToPoint lsf = do
        hashes <- sdlGetSlotHash (envDataLayer env) (lsfSlotNo lsf)
        let valid  = find (\(_, h) -> lsfHash lsf == hashToAnnotation h) hashes
        case valid of
          Just (slot, hash) | slot == lsfSlotNo lsf -> pure $ convert (slot, hash)
          _ -> pure Nothing

    convert :: (SlotNo, ByteString) -> Maybe CardanoPoint
    convert (slot, hashBlob) =
      Point . Point.block slot <$> convertHashBlob hashBlob

    convertHashBlob :: ByteString -> Maybe (HeaderHash CardanoBlock)
    convertHashBlob = Just . fromRawHash (Proxy @CardanoBlock)

-- -------------------------------------------------------------------------------------------------

-- This is correct for now, but theoretically these values can change in a HFC event.
-- Hopefully this code will be long gone (replaced when ledger-specs gets a proper API) before
-- this becomes wrong.
calculateStableEpochSlot :: Shelley.ShelleyGenesis era -> EpochSlot
calculateStableEpochSlot cfg =
    EpochSlot $ ceiling (3.0 * secParam / actSlotCoeff)
  where
    secParam :: Double
    secParam = fromIntegral $ Shelley.sgSecurityParam cfg

    actSlotCoeff :: Double
    actSlotCoeff = fromRational (Ledger.unboundRational $ Shelley.sgActiveSlotsCoeff cfg)
