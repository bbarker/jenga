{-# LANGUAGE OverloadedStrings #-}
module Jenga.Cabal
  ( CabalFilePath (..)
  , dependencyName
  , readPackageDependencies
  , readPackageFromCabalFile
  ) where

-- You would think that since the Cabal file exposes its cabal parser you would
-- think it would be a simple matter to extract the list of dependencies.
-- Unfortunately its much more work than it should be. See:
-- https://hackage.haskell.org/package/Cabal-1.24.2.0/docs/Distribution-PackageDescription.html#v:buildDepends

import           Control.Monad.Trans.Either (EitherT, handleIOEitherT)

import qualified Data.Map.Strict as Map
import           Data.Text (Text)
import qualified Data.Text as Text

import           Distribution.Package (Dependency (..), PackageIdentifier (..), unPackageName)
import           Distribution.PackageDescription
                    ( Benchmark, CondTree (..), ConfVar, Executable, GenericPackageDescription (..)
                    , PackageDescription (..), Library, TestSuite
                    )
import           Distribution.PackageDescription.Parsec (readGenericPackageDescription)
import           Distribution.Verbosity (normal)

import           Jenga.Types


newtype CabalFilePath = CabalFilePath FilePath


readPackageDependencies :: CabalFilePath -> EitherT JengaError IO [Dependency]
readPackageDependencies (CabalFilePath fpath) = do
  handleIOEitherT (JengaIOError "readPackageDependencies" fpath) $ do
    genpkg <- readGenericPackageDescription normal fpath
    pure
      . sortNubByName
      . filterPackageName (package $ packageDescription genpkg)
      $ extractLibraryDeps (condLibrary genpkg)
          ++ extractExecutableDeps (condExecutables genpkg)
          ++ extractTestSuiteDeps (condTestSuites genpkg)
          ++ extractBenchmarkDeps (condBenchmarks genpkg)


readPackageFromCabalFile :: CabalFilePath -> EitherT JengaError IO Package
readPackageFromCabalFile (CabalFilePath fpath) =
  handleIOEitherT (JengaIOError "readPackageFromCabalFile" fpath) $ do
    pkgId <- package . packageDescription <$> readGenericPackageDescription normal fpath
    pure $ Package (Text.pack . unPackageName $ pkgName pkgId) (pkgVersion pkgId)


-- -----------------------------------------------------------------------------

sortNubByName :: [Dependency] -> [Dependency]
sortNubByName = fmap toDep . Map.toList . Map.fromList . fmap fromDep
  where
    fromDep (Dependency n v) = (n, v)
    toDep (n, v) = Dependency n v

filterPackageName :: PackageIdentifier -> [Dependency] -> [Dependency]
filterPackageName (PackageIdentifier pname _) =
  filter (\dep -> pname /= pName dep )
  where
    pName (Dependency pn _) = pn

dependencyName :: Dependency -> Text
dependencyName (Dependency name _) = Text.pack $ unPackageName name


extractLibraryDeps :: Maybe (CondTree ConfVar [Dependency] Library) -> [Dependency]
extractLibraryDeps Nothing = []
extractLibraryDeps (Just x) = condTreeConstraints x

extractExecutableDeps :: [(a, CondTree ConfVar [Dependency] Executable)] -> [Dependency]
extractExecutableDeps = concatMap (condTreeConstraints . snd)

extractTestSuiteDeps :: [(a, CondTree ConfVar [Dependency] TestSuite)] -> [Dependency]
extractTestSuiteDeps = concatMap (condTreeConstraints . snd)

extractBenchmarkDeps :: [(a, CondTree ConfVar [Dependency] Benchmark)] -> [Dependency]
extractBenchmarkDeps = concatMap (condTreeConstraints . snd)
