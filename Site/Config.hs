{-# LANGUAGE OverloadedStrings #-}

-- | Edit this file to make changes. The advantage of spliting it out
-- is that now each module can import this stuff.

module Site.Config where

import Hakyll
import Text.Pandoc

contentsDir  :: String -- ^ Where the actual webpage source reside
contentsDir  = "contents"

rsyncDest :: String -- ^ Where to sync stuff to
rsyncDest = "../piyush-kurur.github.com"

-- | Pandoc reader options.
readerOptions :: ReaderOptions
readerOptions = defaultHakyllReaderOptions

-- | Pandoc writer options.
writerOptions :: WriterOptions
writerOptions = defaultHakyllWriterOptions
   { writerHTMLMathMethod = MathML Nothing -- ^ I want math rendering
   }


-- | Plugins to use for processing Pandoc
plugins :: Pandoc -> Compiler Pandoc
plugins = return

----------------   Templates ------------------------------------------

wrapperT :: Identifier
wrapperT = "templates/wrapper.html"

layoutT  :: Identifier
layoutT  = "templates/layout.html"