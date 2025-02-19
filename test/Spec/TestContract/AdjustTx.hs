module Spec.TestContract.AdjustTx (
  runAdjustTest,
) where

import Control.Lens.Operators ((^.))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Void (Void)
import Ledger (
  PaymentPubKeyHash,
  Tx (..),
  getCardanoTxId,
 )
import Ledger qualified
import Ledger.Ada qualified as Ada
import Ledger.Constraints qualified as Constraints
import Ledger.Constraints.OffChain qualified as OffChain
import Ledger.Value (Value)
import Plutus.Contract (
  Contract,
  adjustUnbalancedTx,
  awaitTxConfirmed,
  mkTxConstraints,
 )
import Plutus.Contract qualified as Contract
import Plutus.PAB.Effects.Contract.Builtin (EmptySchema)
import Test.Plutip.Contract (
  TestWallets,
  assertExecution,
  initAda,
  withContract,
 )
import Test.Plutip.Internal.BotPlutusInterface.Wallet (BpiWallet)
import Test.Plutip.Internal.Types (ClusterEnv)
import Test.Plutip.Predicate (
  shouldSucceed,
  yieldSatisfies,
 )
import Test.Tasty (TestTree)
import Prelude

adjustTx :: PaymentPubKeyHash -> Contract () EmptySchema Text [Value]
adjustTx toPkh = do
  ownPkh <- Contract.ownFirstPaymentPubKeyHash
  let ownAddr = Ledger.pubKeyHashAddress ownPkh Nothing
  utxos <- Contract.utxosAt ownAddr
  let consts =
        Constraints.mustPayToPubKey toPkh (Ada.lovelaceValueOf 50)
      lkups =
        Constraints.ownPaymentPubKeyHash ownPkh
          <> Constraints.unspentOutputs utxos
  unbalancedTx <- mkTxConstraints @Void lkups consts
  -- Adjust the Tx so that all UTxOs have the minimum ADA.
  adjustedTx <- adjustUnbalancedTx unbalancedTx
  let rawTx = adjustedTx ^. OffChain.tx
      vals = map Ledger.txOutValue $ txOutputs rawTx
  balTx <- Contract.balanceTx adjustedTx
  crdTx <- Contract.submitBalancedTx balTx
  _ <- awaitTxConfirmed (getCardanoTxId crdTx)
  pure vals

adjustTx' :: [PaymentPubKeyHash] -> Contract () EmptySchema Text [Value]
adjustTx' [] = do
  pkh <- Contract.ownFirstPaymentPubKeyHash
  adjustTx pkh
adjustTx' (pkh : _) = adjustTx pkh

-- | A type for the output of `assertExecution`.
type PlutipTest = (TestWallets, IO (ClusterEnv, NonEmpty.NonEmpty BpiWallet) -> TestTree)

-- | Tests whether `adjustUnbalancedTx` actually tops up the
-- UTxO to get to the minimum required ADA.
runAdjustTest :: PlutipTest
runAdjustTest =
  assertExecution
    "Adjust Unbalanced Tx Contract"
    (initAda [1000] <> initAda [1000])
    (withContract adjustTx')
    [ shouldSucceed
    , yieldSatisfies
        "All UTxOs have minimum(?) ADA."
        (all (\val -> 500_000 <= Ada.getLovelace (Ada.fromValue val)))
    ]
