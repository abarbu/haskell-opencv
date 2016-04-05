{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module OpenCV.Exception
    ( -- * Exception type
      CvException

      -- * Handling C++ exceptions
    , handleCvException

      -- * Quasi quoters
    , cvExcept
    , cvExceptU

      -- * Monadic interface
    , CvExcept
    , CvExceptT
    , pureExcept

      -- * Promoting exceptions to errors
    , exceptError
    , exceptTError
    , exceptTErrorM

      -- * Unsafe stuff
    , unsafeCvExcept
    , unsafeWrapException
    ) where

import "base" Control.Exception ( Exception, mask_, throw, throwIO )
import "base" Control.Monad ( (<=<) )
import "base" Data.Functor.Identity
import "base" Data.Monoid ( (<>) )
import "base" Foreign.C.String ( peekCString )
import "base" Foreign.ForeignPtr ( ForeignPtr, withForeignPtr )
import "base" Foreign.Ptr ( Ptr, nullPtr )
import "base" System.IO.Unsafe ( unsafePerformIO )
import qualified "inline-c" Language.C.Inline as C
import qualified "inline-c" Language.C.Inline.Unsafe as CU
import qualified "inline-c-cpp" Language.C.Inline.Cpp as C
import "template-haskell" Language.Haskell.TH.Quote ( QuasiQuoter, quoteExp )
import "this" OpenCV.C.Inline ( openCvCtx )
import "this" OpenCV.C.Types
import "this" OpenCV.Internal ( objFromPtr )
import "transformers" Control.Monad.Trans.Except

--------------------------------------------------------------------------------

C.context openCvCtx

C.include "opencv2/core.hpp"
C.using "namespace cv"


--------------------------------------------------------------------------------
-- Exceptions
--------------------------------------------------------------------------------

newtype CvException = CvException { unCvException :: ForeignPtr (C CvException) }

type instance C CvException = C'CvException

instance WithPtr CvException where
    withPtr = withForeignPtr . unCvException

instance FromPtr CvException where
    fromPtr = objFromPtr CvException $ \ptr ->
                [CU.exp| void { delete $(Exception * ptr) }|]

instance Exception CvException

instance Show CvException where
    show cvException = unsafePerformIO $
        withPtr cvException $ \cvExceptionPtr -> do
          charPtr <- [CU.exp| const char * { $(Exception * cvExceptionPtr)->what() } |]
          peekCString charPtr

handleCvException
    :: IO a
    -> IO (Ptr (C CvException))
    -> IO (Either CvException a)
handleCvException okAct act = mask_ $ do
    exceptionPtr <- act
    if exceptionPtr /= nullPtr
      then Left <$> fromPtr (pure exceptionPtr)
      else Right <$> okAct

cvExcept :: QuasiQuoter
cvExcept = C.block {quoteExp = \s -> quoteExp C.block $ cvExceptWrap s}

cvExceptU :: QuasiQuoter
cvExceptU = CU.block {quoteExp = \s -> quoteExp CU.block $ cvExceptWrap s}

cvExceptWrap :: String -> String
cvExceptWrap s =
    "Exception * {\n\
    \  try\n\
    \  {\n   " <> s <> "\n\
    \    return NULL;\n\
    \  }\n\
    \  catch (const cv::Exception & e)\n\
    \  {\n\
    \    return new cv::Exception(e);\n\
    \  }\n\
    \}"

type CvExcept    a = Except  CvException   a
type CvExceptT m a = ExceptT CvException m a

pureExcept :: (Applicative m) => CvExcept a -> CvExceptT m a
pureExcept = mapExceptT (pure . runIdentity)

exceptError :: CvExcept a -> a
exceptError = either throw id . runExcept

exceptTError :: CvExceptT IO a -> IO a
exceptTError = either throwIO pure <=< runExceptT

exceptTErrorM :: (Monad m) => CvExceptT m a -> m a
exceptTErrorM = either throw pure <=< runExceptT

unsafeCvExcept :: CvExceptT IO a -> CvExcept a
unsafeCvExcept = mapExceptT (Identity . unsafePerformIO)

unsafeWrapException :: IO (Either CvException a) -> CvExcept a
unsafeWrapException = unsafeCvExcept . ExceptT