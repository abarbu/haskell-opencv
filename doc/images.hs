{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import "base" Data.Functor ( void )
import "base" Data.Foldable ( forM_ )
import "base" Data.Int
import "base" Data.Monoid ( (<>) )
import "base" Data.Proxy
import "base" Data.Word
import "base" GHC.TypeLits
import "base" System.IO.Unsafe ( unsafePerformIO )
import qualified "bytestring" Data.ByteString as B
import "linear" Linear.Vector ( (^+^) )
import "linear" Linear.V2 ( V2(..) )
import "linear" Linear.V4 ( V4(..) )
import qualified "text" Data.Text as T
import "thea" OpenCV
import "thea" OpenCV.Unsafe
import qualified "vector" Data.Vector as V
import "transformers" Control.Monad.Trans.Class ( lift )

import "this" ExampleExtractor ( render, extractExampleImages )

--------------------------------------------------------------------------------

transparent, white, black, blue, red :: Scalar
transparent = convert (V4 255 255 255   0 :: V4 Double)
white       = convert (V4 255 255 255 255 :: V4 Double)
black       = convert (V4   0   0   0 255 :: V4 Double)
blue        = convert (V4 255   0   0 255 :: V4 Double)
red         = convert (V4   0   0 255 255 :: V4 Double)

type Birds_768x512 = Mat (ShapeT [512, 768]) ('S 3) ('S Word8)
type Birds_512x341 = Mat (ShapeT [341, 512]) ('S 3) ('S Word8)
type Frog          = Mat (ShapeT [390, 500]) ('S 3) ('S Word8)
type Lambda        = Mat (ShapeT [256, 256]) ('S 1) ('S Word8)

birds_768x512 :: Birds_768x512
birds_768x512 = either (error . concat) id $ coerceMat $ unsafePerformIO $
                  imdecode ImreadColor <$> B.readFile "data/kodim23.png"

birds_512x341 :: Birds_512x341
birds_512x341 = either (error . concat) id $ coerceMat $
                  exceptError $
                  resize (ResizeAbs $ convert (V2 512 341 :: V2 Int32))
                         InterArea
                         birds_768x512

frog :: Frog
frog = either (error . concat) id $ coerceMat $ unsafePerformIO $
         imdecode ImreadColor <$> B.readFile "data/kikker.jpg"

lambda :: Lambda
lambda = either (error . concat) id $ coerceMat $ unsafePerformIO $
           imdecode ImreadGrayscale <$> B.readFile "data/lambda.png"

--------------------------------------------------------------------------------

-- We use some padding around the small image in which we draw the
-- lines. This is because antialiasing doesn't seem to work near the
-- edges of an image.
lineTypeImg
    :: forall (h :: Nat) (w :: Nat) (p :: Nat)
     . ( h ~ 5
       , w ~ (h * 3)
       , p ~ 20
       )
    => LineType
    -> Mat ('S ['D, 'D]) ('S 4) ('S Word8)
lineTypeImg lineType = exceptError $ do
    img <- withMatM (h + 2 * p ::: w + 2 * p ::: Z)
                    (Proxy :: Proxy 4)
                    (Proxy :: Proxy Word8)
                    transparent $ \imgM -> do
             lift $ line imgM (pure p + V2 0 h) (pure p + V2 w 0) black 1 lineType 0
    resize (ResizeRel $ pure zoom) InterNearest
           =<< matSubRect img (mkRect (pure p) (V2 w h))
  where
    w, h, p :: Int32
    w = fromInteger $ natVal (Proxy :: Proxy w)
    h = fromInteger $ natVal (Proxy :: Proxy h)
    p = fromInteger $ natVal (Proxy :: Proxy p)
    zoom = 8

fontFaceImg
    :: FontFace
    -> Mat ('S ['D, 'D]) ('S 4) ('S Word8)
fontFaceImg fontFace = exceptError $
    withMatM (th * 3 ::: tw ::: Z)
             (Proxy :: Proxy 4)
             (Proxy :: Proxy Word8)
             transparent $ \imgM -> do
      putText imgM txt (V2 0 (th * 2 - baseLine) :: V2 Int32) fontFace scale black thickness LineType_AA False
  where
    txt = "The quick brown fox jumps over the lazy dog"
    (size2i, baseLine) = getTextSize txt fontFace scale thickness
    tw, th :: Int32
    V2 tw th = convert size2i
    scale     = 1
    thickness = 1


--------------------------------------------------------------------------------

extractExampleImages "src"

--------------------------------------------------------------------------------

main :: IO ()
main = do
    renderExampleImages
    render "birds_512x341.png" birds_512x341
    forM_ [minBound .. maxBound] $ \lineType ->
      render (show lineType <> ".png") (lineTypeImg lineType)
    forM_ [minBound .. maxBound] $ \fontFace ->
      render (show fontFace <> ".png") (fontFaceImg fontFace)

--------------------------------------------------------------------------------