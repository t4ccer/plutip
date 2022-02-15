module Main (main) where

import Control.Monad (forever, replicateM_, void)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Text (Text, unpack)
import DebugContract.GetUtxos qualified as GetUtxos
import DebugContract.LockUnlock qualified as LockUnlock 
import DebugContract.LockUnlockValidationFail qualified as LockUnlockValidationFail 
import DebugContract.PayToWallet qualified as PayToWallet
import System.Environment (setEnv)
import System.IO (BufferMode (NoBuffering), hSetBuffering, stderr, stdout)
import Test.Plutip (
  ada,
  addSomeWallet,
  andThen,
  ledgerPaymentPkh,
  mkMainnetAddress,
  report,
  runContract,
  runContractTagged,
  runUsingCluster,
  waitSeconds,
 )
import Test.Plutip.LocalCluster.Types (supportDir)

main :: IO ()
main = do
  runUsingCluster $ do
    testW1 <- addSomeWallet (ada 101)
    testW2 <- addSomeWallet (ada 202)
    waitSeconds 2 -- wait for transactions to submit

    -- 1 successful and 2 failing scenarios
    runContract testW1 GetUtxos.getUtxos
      `andThen` report
    runContractTagged "Throws Contract error" testW1 GetUtxos.getUtxosThrowsErr
      `andThen` report
    runContractTagged "Throws Exception" testW1 GetUtxos.getUtxosThrowsEx
      `andThen` report

    -- successful wallet to wallet transaction
    let p2pContract = PayToWallet .payTo (ledgerPaymentPkh testW2) 10_000_000
    runContractTagged "Pay wallet-to-wallet" testW1 p2pContract
      `andThen` report

    -- budget overspend script
    runContractTagged
      "Lock at script then spend - budget overspend"
      testW1
      LockUnlock .lockThenSpend
      `andThen` report

    -- validation fail script
    runContractTagged
      "Lock at script then spend - validation fail"
      testW1
      LockUnlockValidationFail .lockThenSpend
      `andThen` report

    liftIO $ putStrLn "Done. Debug awaiting - Enter to exit" >> void getLine
