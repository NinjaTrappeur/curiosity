{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE KindSignatures #-}
module Curiosity.Data.Counter
  ( CounterValue(..)
  , Counter(..)
  , CounterStep(..)
  , bumpCounterPrefix
  ) where

import qualified Control.Concurrent.STM        as STM
import           Data.Aeson

-- | Counter step: a principled datatype (vs. a bespoke pair) that stores the current and previous value of some count.
data CounterStep count = CounterStep
  { was :: count -- ^ Previous value.
  , is  :: count -- ^ New value (stepped/bumped value). This is the value stored in the counter.
  }
  deriving (Eq, Show)

newtype CounterValue (datastore :: Type -> Type) count = CounterValue { counterValue :: datastore count }
                                                       deriving (Eq, Show)
                                                       deriving (ToJSON, FromJSON) via datastore count

instance Functor datastore => Functor (CounterValue datastore) where
  fmap f (CounterValue dcount) = CounterValue $ fmap f dcount
instance Applicative datastore => Applicative (CounterValue datastore) where
  pure = CounterValue . pure
  liftA2 f (CounterValue dcount0) (CounterValue dcount1) =
    CounterValue $ liftA2 f dcount0 dcount1

class Counter count datastore m where

  -- | Generate the initial value of a counter.
  newCounter :: count ->  m (CounterValue datastore count)

  -- | Generate the next value of a counter.
  readCounter :: CounterValue datastore count -> m count

  -- | Set the value of a counter.
  writeCounter :: CounterValue datastore count -> count -> m ()

  -- | Bump the counter value, returning the value before and after the bump.
  bumpCounter :: CounterValue datastore count -> m (CounterStep count)

instance Enum count => Counter count STM.TVar STM.STM  where

  newCounter initCount = CounterValue <$> STM.newTVar initCount

  readCounter (CounterValue countTvar) = STM.readTVar countTvar

  writeCounter (CounterValue countTvar) count = STM.writeTVar countTvar count

  bumpCounter ctr@(CounterValue countTvar) = do
    was <- readCounter ctr
    let is = succ was
    STM.writeTVar countTvar is
    pure CounterStep { .. }

-- | Since we're dealing with pure values, bumpCounter has no effect.
instance Enum count => Counter count Identity Identity where

  newCounter initCount = pure $ CounterValue . Identity $ initCount

  readCounter (CounterValue (Identity curValue)) = pure curValue

  writeCounter (CounterValue _) _ = pure ()

  bumpCounter (CounterValue (Identity curValue)) =
    pure CounterStep { was = curValue, is = succ curValue }

-- | Get the current value of a counter bumping the value as we go.
bumpCounterPrefix
  :: forall count m datastore
   . (Counter count datastore m, Applicative m, Show count)
  => Text
  -> CounterValue datastore count
  -> m Text
bumpCounterPrefix prefix ctr = bumpCounter ctr <&> mappend prefix . show . was

