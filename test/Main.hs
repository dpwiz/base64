{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PackageImports #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
-- |
-- Module       : Main
-- Copyright    : (c) 2019-2020 Emily Pillmore
-- License      : BSD-style
--
-- Maintainer   : Emily Pillmore <emilypi@cohomolo.gy>
-- Stability    : Experimental
-- Portability  : portable
--
-- This module contains the test implementation for the `base64` package
--
module Main
( main
) where

import Prelude hiding (length)

import qualified Data.ByteString as BS
import Data.ByteString.Internal (c2w)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Short as SBS
import "base64" Data.ByteString.Base64 as B64
import "base64" Data.ByteString.Base64.URL as B64U
import qualified "base64-bytestring" Data.ByteString.Base64 as Bos
import qualified "base64-bytestring" Data.ByteString.Base64.URL as BosU
import Data.Proxy
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Short as TS
import Data.Word

import Internal

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck (testProperty)


main :: IO ()
main = defaultMain tests


tests :: TestTree
tests = testGroup "Base64 Tests"
  [ mkTree (Proxy :: Proxy B64)
    [ mkPropTree
    , mkUnitTree BS.last BS.length
    ]
  , mkTree (Proxy :: Proxy LB64)
    [ mkPropTree
    , mkUnitTree LBS.last (fromIntegral . LBS.length)
    ]
  , mkTree (Proxy :: Proxy SB64)
    [ mkPropTree
    , mkUnitTree (BS.last . SBS.fromShort) SBS.length
    ]
  , mkTree (Proxy :: Proxy T64)
    [ mkPropTree
    , mkUnitTree (c2w . T.last) T.length
    ]
  , mkTree (Proxy :: Proxy TL64)
    [ mkPropTree
    , mkUnitTree (c2w . TL.last) (fromIntegral . TL.length)
    ]
  , mkTree (Proxy :: Proxy TS64)
    [ mkPropTree
    , mkUnitTree (c2w . T.last . TS.toText) TS.length
    ]
  ]

mkTree :: forall a b proxy. Harness a b => proxy a -> [proxy a -> TestTree] -> TestTree
mkTree a = testGroup (label @a) . fmap ($ a)

mkPropTree :: forall a b proxy. Harness a b => proxy a -> TestTree
mkPropTree a = testGroup "Property Tests"
  [ prop_roundtrip a
  , prop_correctness a
  , prop_url_padding a
  , prop_bos_coherence
  ]

mkUnitTree
  :: forall a b proxy
  . Harness a b
  => (b -> Word8)
  -> (b -> Int)
  -> proxy a
  -> TestTree
mkUnitTree last_ length_ a = testGroup "Unit tests"
  [ paddingTests a last_ length_
  , rfcVectors a
  ]
-- ---------------------------------------------------------------- --
-- Property tests


prop_roundtrip :: forall a b proxy. Harness a b => proxy a -> TestTree
prop_roundtrip _ = testGroup "prop_roundtrip"
  [ testProperty "prop_std_roundtrip" $ \(bs :: b) ->
      Right (encode bs) == decode (encode (encode bs))
  , testProperty "prop_url_roundtrip" $ \(bs :: b) ->
      Right (encodeUrl bs) == decodeUrl (encodeUrl (encodeUrl bs))
  , testProperty "prop_url_roundtrip_nopad" $ \(bs :: b) ->
      Right (encodeUrlNopad bs)
        == decodeUrlNopad (encodeUrlNopad (encodeUrlNopad bs))
  , testProperty "prop_std_lenient_roundtrip" $ \(bs :: b) ->
      encode bs == lenient (encode (encode bs))
  , testProperty "prop_url_lenient_roundtrip" $ \(bs :: b) ->
      encodeUrl bs == lenientUrl (encodeUrl (encodeUrl bs))
  ]

prop_correctness :: forall a b proxy. Harness a b => proxy a -> TestTree
prop_correctness _ = testGroup "prop_validity"
  [ testProperty "prop_std_valid" $ \(bs :: b) ->
    validate (encode bs)
  , testProperty "prop_url_valid" $ \(bs :: b) ->
    validateUrl (encodeUrl bs)
  , testProperty "prop_std_correct" $ \(bs :: b) ->
    correct (encode bs)
  , testProperty "prop_url_correct" $ \(bs :: b) ->
    correctUrl (encodeUrl bs)
  ]

prop_url_padding :: forall a b proxy. Harness a b => proxy a -> TestTree
prop_url_padding _ = testGroup "prop_url_padding"
  [ testProperty "prop_url_nopad_roundtrip" $ \(bs :: b) ->
      Right (encodeUrlNopad bs)
        == decodeUrlNopad (encodeUrlNopad (encodeUrlNopad bs))

  , testProperty "prop_url_pad_roundtrip" $ \(bs :: b) ->
      Right (encodeUrl bs) == decodeUrlPad (encodeUrl (encodeUrl bs))

  , testProperty "prop_url_decode_invariant" $ \(bs :: b) ->
      ( decodeUrlNopad (encodeUrlNopad (encodeUrlNopad bs))
      == decodeUrl (encodeUrl (encodeUrl bs))
      ) ||
      ( decodeUrlPad (encodeUrl (encodeUrl bs))
      == decodeUrl (encodeUrl (encodeUrl bs))
      )

  -- NOTE: we need to fix the bitmasking issue for "impossible"
  -- inputs

  , testProperty "prop_url_padding_coherence" $ \(bs :: b) ->
      Right (encodeUrl bs) == decodeUrl (encodeUrl (encodeUrl bs))
      && Right (encodeUrl bs) == decodeUrlPad (encodeUrl (encodeUrl bs))

  , testProperty "prop_url_nopadding_coherence" $ \(bs :: b) ->
      Right (encodeUrlNopad bs) == decodeUrlNopad (encodeUrlNopad (encodeUrlNopad bs))
      && Right (encodeUrlNopad bs) == decodeUrl (encodeUrlNopad (encodeUrlNopad bs))
  ]


prop_bos_coherence :: TestTree
prop_bos_coherence = testGroup "prop_bos_coherence"
  [ testProperty "prop_std_bos_coherence" $ \bs ->
      Right bs == B64.decodeBase64 (B64.encodeBase64' bs)
      && Right bs == Bos.decode (Bos.encode bs)
  , testProperty "prop_url_bos_coherence" $ \bs ->
      Right bs == B64U.decodeBase64 (B64U.encodeBase64' bs)
      && Right bs == BosU.decode (BosU.encode bs)
  ]

-- ---------------------------------------------------------------- --
-- Unit tests

rfcVectors :: forall a b proxy. Harness a b => proxy a -> TestTree
rfcVectors _ = testGroup "RFC 4648 Test Vectors"
    [ testGroup "std alphabet"
      [ testCaseStd "" ""
      , testCaseStd "f" "Zg=="
      , testCaseStd "f" "Zg=="
      , testCaseStd "fo" "Zm8="
      , testCaseStd "foo" "Zm9v"
      , testCaseStd "foob" "Zm9vYg=="
      , testCaseStd "fooba" "Zm9vYmE="
      , testCaseStd "foobar" "Zm9vYmFy"
      ]
    , testGroup "url-safe alphabet"
      [ testCaseUrl "" ""
      , testCaseUrl "<" "PA=="
      , testCaseUrl "<<" "PDw="
      , testCaseUrl "<<?" "PDw_"
      , testCaseUrl "<<??" "PDw_Pw=="
      , testCaseUrl "<<??>" "PDw_Pz4="
      , testCaseUrl "<<??>>" "PDw_Pz4-"
      ]
    ]
  where
    testCaseStd s t = testCase (show $ if s == "" then "empty" else s) $ do
      t @=? encode @a s
      Right s @=? decode @a (encode @a s)

    testCaseUrl s t = testCase (show $ if s == "" then "empty" else s) $ do
      t @=? encodeUrl @a s
      Right s @=? decodeUrlPad @a t

paddingTests
  :: forall a b proxy
  . Harness a b
  => proxy a
  -> (b -> Word8)
  -> (b -> Int)
  -> TestTree
paddingTests _ last_ length_ = testGroup "Padding tests"
    [ testGroup "URL decodePadding coherence"
      [ ptest "<" "PA=="
      , ptest "<<" "PDw="
      , ptest "<<?" "PDw_"
      , ptest "<<??" "PDw_Pw=="
      , ptest "<<??>" "PDw_Pz4="
      , ptest "<<??>>" "PDw_Pz4-"
      ]
    , testGroup "URL decodeUnpadded coherence"
      [ utest "<" "PA"
      , utest "<<" "PDw"
      , utest "<<?" "PDw_"
      , utest "<<??" "PDw_Pw"
      , utest "<<??>" "PDw_Pz4"
      , utest "<<??>>" "PDw_Pz4-"
      ]
    ]
  where
    ptest :: b -> b -> TestTree
    ptest s t =
      testCaseSteps (show $ if t == "" then "empty" else t) $ \step -> do
        let u = decodeUrlNopad @a t
            v = decodeUrlPad @a t

        if last_ t == 0x3d then do
          step "Padding required: no padding fails"
          u @=? Left "Base64-encoded bytestring has invalid padding"

          step "Padding required: padding succeeds"
          v @=? Right s
        else do
          step "String has no padding: decodes should coincide"
          u @=? Right s
          v @=? Right s
          v @=? u

    utest :: b -> b -> TestTree
    utest s t =
      testCaseSteps (show $ if t == "" then "empty" else t) $ \step -> do
        let u = decodeUrlPad @a t
            v = decodeUrlNopad @a t

        if length_ t `mod` 4 == 0 then do
          step "String has no padding: decodes should coincide"
          u @=? Right s
          v @=? Right s
          v @=? u
        else do
          step "Unpadded required: padding fails"
          u @=? Left "Base64-encoded bytestring requires padding"

          step "Unpadded required: unpadding succeeds"
          v @=? Right s
