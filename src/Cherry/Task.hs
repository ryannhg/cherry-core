module Cherry.Task
  ( -- * Tasks
    -- Tasks make it easy to describe asynchronous operations that may fail, like
    -- HTTP requests or writing to a database.
    Task, perform

    -- * Chains
  , andThen, succeed, fail, sequence

    -- * Interop
  , enter, exit

    -- * Maps
  , map, map2, map3, map4, map5, map6

    -- * Errors
  , onError, mapError
  ) where

import qualified Prelude as P
import qualified Data.Text as Text
import qualified Data.List
import qualified GHC.Stack as Stack
import qualified Cherry.Internal.Task as Task
import qualified Cherry.List as List
import Prelude (IO, FilePath, (<>))
import Cherry.Basics
import Cherry.List (List)
import Cherry.Result (Result(..))
import Cherry.Maybe (Maybe(..))


{-| A task is a _description_ of what you need to do. Like a todo
list. Or like a grocery list. Or like GitHub issues. So saying "the task is
to tell me the current POSIX time" does not complete the task! You need
[`perform`](#perform) tasks or [`attempt`](#attempt) tasks.
-}
type Task x a =
  Task.Task x a


-- BASICS


{-| Just having a `Task` does not mean it is done. We must `perform` the task:

  >  import Cherry.Task
  >  import Cherry.Task
  >
  >  main :: Program
  >  main =
  >    Task.perform Log.none Time.now

-}
perform :: Task.Output -> Task x a -> IO (Result x a)
perform =
  Task.perform


{-| A task that succeeds immediately when run. It is usually used with
[`andThen`](#andThen). You can use it like `map` if you want:

  >  import Time
  >
  >  timeInMillis : Task x Int
  >  timeInMillis =
  >    Time.now
  >      |> andThen (\t -> succeed (Time.posixToMillis t))

-}
succeed :: a -> Task x a
succeed =
  Task.succeed


{-| A task that fails immediately when run. Like with `succeed`, this can be
used with `andThen` to check on the outcome of another task.

  >  type Error = NotFound
  >
  >  notFound : Task Error a
  >  notFound =
  >    fail NotFound
-}
fail :: x -> Task x a
fail =
  Task.fail



-- MAPS


{-| Transform a task. Maybe you want to use [`elm/time`][time] to figure
out what time it will be in one hour:

  >  import Task exposing (Task)
  >  import Time -- elm install elm/time
  >
  >  timeInOneHour : Task x Time.Posix
  >  timeInOneHour =
  >    Task.map addAnHour Time.now
  >
  >  addAnHour : Time.Posix -> Time.Posix
  >  addAnHour time =
  >    Time.millisToPosix (Time.posixToMillis time + 60 * 60 * 1000)

[time]: /packages/elm/time/latest/
-}
map :: (a -> b) -> Task x a -> Task x b
map =
  Task.map


{-| Put the results of two tasks together. For example, if we wanted to know
the current month, we could use [`elm/time`][time] to ask:

  >  import Task exposing (Task)
  >  import Time -- elm install elm/time
  >
  >  getMonth : Task x Int
  >  getMonth =
  >    Task.map2 Time.toMonth Time.here Time.now

**Note:** Say we were doing HTTP requests instead. `map2` does each task in
order, so it would try the first request and only continue after it succeeds.
If it fails, the whole thing fails!

[time]: /packages/elm/time/latest/
-}
map2 :: (a -> b -> result) -> Task x a -> Task x b -> Task x result
map2 =
  Task.map2


{-| -}
map3 :: (a -> b -> c -> result) -> Task x a -> Task x b -> Task x c -> Task x result
map3 =
  Task.map3


{-| -}
map4 :: (a -> b -> c -> d -> result) -> Task x a -> Task x b -> Task x c -> Task x d -> Task x result
map4 =
  Task.map4


{-| -}
map5 :: (a -> b -> c -> d -> e -> result) -> Task x a -> Task x b -> Task x c -> Task x d -> Task x e -> Task x result
map5 =
  Task.map5


{-| -}
map6 :: (a -> b -> c -> d -> e -> f -> result) -> Task x a -> Task x b -> Task x c -> Task x d -> Task x e -> Task x f -> Task x result
map6 =
  Task.map6


{-| Chain together a task and a callback. The first task will run, and if it is
successful, you give the result to the callback resulting in another task. This
task then gets run. We could use this to make a task that resolves an hour from
now:

  >  import Time -- elm install elm/time
  >  import Process
  >
  >  timeInOneHour : Task x Time.Posix
  >  timeInOneHour =
  >    Process.sleep (60 * 60 * 1000)
  >      |> andThen (\_ -> Time.now)

First the process sleeps for an hour **and then** it tells us what time it is.
-}
andThen :: (a -> Task x b) -> Task x a -> Task x b
andThen =
  Task.andThen


{-| Start with a list of tasks, and turn them into a single task that returns a
list. The tasks will be run in order one-by-one and if any task fails the whole
sequence fails.

  >  sequence [ succeed 1, succeed 2 ] == succeed [ 1, 2 ]

-}
sequence :: List (Task x a) -> Task x (List a)
sequence =
  Task.sequence


{-| Recover from a failure in a task. If the given task fails, we use the
callback to recover.

  >  fail "file not found"
  >    |> onError (\msg -> succeed 42)
  >    -- succeed 42
  >
  >  succeed 9
  >    |> onError (\msg -> succeed 42)
  >    -- succeed 9
-}
onError :: (x -> Task y a) -> Task x a -> Task y a
onError =
  Task.onError


{-| Transform the error value. This can be useful if you need a bunch of error
types to match up.

  >  type Error
  >    = Http Http.Error
  >    | WebGL WebGL.Error
  >
  >  getResources : Task Error Resource
  >  getResources =
  >    sequence
  >      [ mapError Http serverTask
  >      , mapError WebGL textureTask
  >      ]
-}
mapError :: (x -> y) -> Task x a -> Task y a
mapError =
  Task.mapError



-- INTEROP


{-| When working with third party libraries, you might need to
transform an `IO` into a `Task`. If that is the case, use this function.

You shouldn't usually need to use this!
-}
enter :: IO (Result x a) -> Task x a
enter =
  Task.enter


{-| When working with third party libraries, you might need to
transform a `Task` into an `IO`. If that is the case, use this function.

You shouldn't usually need to use this!
-}
exit :: Task x a -> IO (Result x a)
exit =
  Task.exit

