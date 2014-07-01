{-# LANGUAGE ScopedTypeVariables #-}

module Control.Auto.Collection where

import Control.Applicative
import Control.Arrow
import Control.Auto.Core
import Control.Auto.Event.Internal
import Control.Monad hiding        (mapM, mapM_)
import Data.Binary
import Data.Foldable
import Data.Map.Strict             (Map)
import Data.Monoid
import Data.Traversable
import Prelude hiding              (mapM, mapM_)
import qualified  Data.Map.Strict  as M

zipAuto :: Monad m => a -> [Auto m a b] -> Auto m [a] [b]
zipAuto x0 as = mkAutoM (zipAuto x0 <$> mapM loadAuto as)
                        (mapM_ saveAuto as)
                        $ \xs -> do
                            res <- zipWithM stepAuto as (xs ++ repeat x0)
                            let ys  = map outRes  res
                                as' = map outAuto res
                            return (Output ys (zipAuto x0 as'))

-- another problem
dynZip_ :: Monad m => a -> Auto m ([a], Event [Auto m a (Maybe b)]) [b]
dynZip_ x0 = go []
  where
    go as = mkAutoM_ $ \(xs, news) -> do
                         let newas = event [] id news
                         res <- zipWithM stepAuto (as ++ newas) (xs ++ repeat x0)
                         let (ys, as') = unzip [ (y, a) | (Output (Just y) a) <- res ]
                         return (Output ys (go as'))

mux :: forall m a b k. (Binary k, Ord k, Monad m) => (k -> Auto m a b) -> Auto m (k, a) b
mux f = go mempty
  where
    go :: Map k (Auto m a b) -> Auto m (k, a) b
    go as = mkAutoM l (s as) $ \(k, x) -> do
                                 let a = M.findWithDefault (f k) k as
                                 Output y a' <- stepAuto a x
                                 let as' = M.insert k a' as
                                 return (Output y (go as'))
    l = do
      ks <- get
      let as' = M.fromList (map (id &&& f) ks)
      go <$> mapM loadAuto as'
    s as = put (M.keys as) *> mapM_ saveAuto as