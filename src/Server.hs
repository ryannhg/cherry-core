{-# LANGUAGE PackageImports #-}

{-|

Module      : Server
Description : Run a server.
License     : BSD 3
Maintainer  : terezasokol@gmail.com
Stability   : experimental
Portability : POSIX

-}

module Server (Route, listen, get, post, text, json, file, body, getLogin, getToken, findHeader) where

import qualified Control.Exception.Safe as Control
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.Maybe as HMaybe
import qualified Data.Either as Either
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Base64 as Base64
import qualified "text-utf8" Data.Text as T
import qualified "text-utf8" Data.Text.Lazy as TL
import qualified "text-utf8" Data.Text.Encoding as Encoding
import qualified "text-utf8" Data.Text.Encoding.Error as Encoding
import qualified Data.Time.Clock.POSIX as POSIX
import qualified Data.CaseInsensitive as CI
import qualified Network.Wai as Wai
import qualified Network.Wai.Handler.Warp as Warp
import qualified Network.Wai.Middleware.Static as Static
import qualified Network.Wai.Middleware.RequestLogger as RequestLogger
import qualified Network.HTTP.Types as HTTP
import qualified Network.HTTP.Types.Method as Method
import qualified Network.HTTP.Types.Header as Header
import qualified Prelude
import qualified Maybe
import qualified String
import qualified Debug
import qualified List
import qualified Tuple
import qualified Http
import qualified Result
import qualified Dict
import qualified Task
import qualified Terminal
import qualified Url
import qualified Url.Parser as Parser
import qualified Interop
import qualified Json.Encode as E
import qualified Json.Decode as D
import Cherry.Prelude
import Url.Parser (Parser)


{-| -}
type Port =
  Int


{-| -}
listen :: Port -> String -> List Route -> Task String ()
listen port public routes =
  let log =
        RequestLogger.logStdoutDev

      static =
        Static.staticPolicy (Static.addBase (String.toList public))

      listen_ =
        Warp.run port application_
          |> Interop.enter
          |> Task.mapError (\_ -> "Could not start server.")

      application_ =
        application public routes
          |> log
          |> static
  in do
  Terminal.write (String.concat [ "Listening on port ", String.fromInt port, "..." ])
  listen_


{-| -}
newtype Route =
  Route (Http.Request -> Url.Url -> Maybe (Task String Http.Response))


{-| -}
get :: Parser a (Task String Http.Response) -> (Http.Request -> a) -> Route
get parser handler =
  Route <| \request url ->
    if Wai.requestMethod request == Method.methodGet then
      Parser.parse (Parser.map (handler request) parser) url
    else
      Nothing


{-| -}
post :: Parser a (Task String Http.Response) -> (Http.Request -> a) -> Route
post parser handler =
  Route <| \request url ->
    if Wai.requestMethod request == Method.methodPost then
      Parser.parse (Parser.map (handler request) parser) url
    else
      Nothing


{-| -}
text :: Int -> String -> Http.Response
text statusNo string =
  Wai.responseLBS (statusCode statusNo) [] (String.toLazyByteString string)


{-| -}
json :: Int -> E.Value -> Http.Response
json statusNo value =
  Wai.responseBuilder (statusCode statusNo) [] (E.toBuilder value)


{-| -}
file :: Int -> String -> Http.Response
file statusNo path =
  Wai.responseFile (statusCode statusNo) [] (String.toList path) HMaybe.Nothing



-- HELPERS


{-| -}
body :: D.Decoder a -> Http.Request -> Task.Task String a
body decoder request =
  let getChunks :: List B.ByteString -> Task.Task String B.ByteString
      getChunks chunks =
        Wai.getRequestBodyChunk request
          |> Interop.enter
          |> Task.mapError (\_ -> "Body could not be parsed")
          |> Task.andThen (\chunk ->
              if chunk == B.empty
              then Task.succeed (B.concat (List.reverse chunks))
              else getChunks (chunk : chunks)
            )

      decode bs =
        String.fromByteString bs
          |> D.fromString decoder
          |> fromResult

      fromResult result =
        case result of
          Ok v -> Task.succeed v
          Err e -> Task.fail "Body could not be parsed"
  in
  getChunks []
    |> Task.andThen decode



-- HELPERS / AUTH


{-| -}
getToken :: Http.Request -> Result String String
getToken request =
  findHeader "Authorization" request
    |> Result.map dropBasic
    |> Result.andThen decodeBase64


{-| -}
getLogin :: Http.Request -> Result String ( String, String )
getLogin request =
  findHeader "Authorization" request
    |> Result.map dropBasic
    |> Result.andThen decodeBase64
    |> Result.andThen textToAuthForm


dropBasic :: String -> String
dropBasic =
  String.dropLeft 6


decodeBase64 :: String -> Result String String
decodeBase64 value =
  value
    |> String.toByteString
    |> Base64.decode
    |> Result.fromEither
    |> Result.mapError String.fromList
    |> Result.map String.fromByteString


textToAuthForm :: String -> Result String ( String, String )
textToAuthForm text =
  case String.split ":" text of
    [ email, password ] -> Ok ( email, password )
    _ -> Err ("Bad value: " ++ text)




-- HELPERS / HEADER


{-| -}
findHeader :: CI.CI B.ByteString -> Http.Request -> Result String String
findHeader name request =
  let isCorrect ( header, value ) = header == name
      getValue ( header, value ) = value
      nameAsError = String.fromByteString (CI.original name)
  in
  findFirst isCorrect (Wai.requestHeaders request)
    |> Maybe.map getValue
    |> Result.fromMaybe ("Request is missing \"" ++ nameAsError ++ "\" header.")
    |> Result.map String.fromByteString


findFirst :: (a -> Bool) -> List a -> Maybe a
findFirst isCorrect all =
  case all of
    a : rest -> if isCorrect a then Just a else findFirst isCorrect rest
    [] -> Nothing



-- INTERNAL


application :: String -> List Route -> Wai.Application
application public routes request respond =
  let url = requestToUrl request
      allRoutes = collectRoutes public routes
  in
  findResponse public url request allRoutes
    |> Task.attempt
    |> Interop.andThen (toSafeResponse >> respond)


requestToUrl :: Http.Request -> Url.Url
requestToUrl request =
  let toPath request =
        Wai.rawPathInfo request
          |> String.fromByteString

      toQuery request =
        Wai.rawQueryString request
          |> B.tail
          |> String.fromByteString
          |> nothingIfEmpty

      nothingIfEmpty string =
        if String.isEmpty string then
          Nothing
        else
          Just string
  in
  Url.Url
    { Url.path = toPath request
    , Url.query = toQuery request
    }


findResponse :: String -> Url.Url -> Http.Request -> List Route -> Task String Http.Response
findResponse public url request remaining =
  case remaining of
    Route next : rest ->
      case next request url of
        Just response -> response
        Nothing -> findResponse public url request rest

    [] ->
        Task.succeed (serve404 public)


collectRoutes :: String -> List Route -> List Route
collectRoutes public routes =
  routes ++ [ homeRoute public ]


homeRoute :: String -> Route
homeRoute public =
  get Parser.top <| \_ ->
    Task.succeed (serveIndex public)


statusCode :: Int -> HTTP.Status
statusCode statusNo =
  case statusNo of
    200 -> HTTP.status200
    404 -> HTTP.status404
    401 -> HTTP.status401
    501 -> HTTP.status501
    _   -> HTTP.status404 -- TODO



-- RESPONSES


serveIndex :: String -> Http.Response
serveIndex public =
  file 200 (String.concat [ public, "/index.html" ])


serve404 :: String -> Http.Response
serve404 public =
  file 404 (String.concat [ public, "/404.html" ])


internalError :: String -> Http.Response
internalError err =
  Wai.responseLBS HTTP.status500 [] (String.toLazyByteString err)


notFound :: Http.Response
notFound =
  Wai.responseLBS HTTP.status404 [] "Route not found"


toSafeResponse :: Result String Http.Response -> Http.Response
toSafeResponse result =
  case result of
    Result.Ok response -> response
    Result.Err msg -> internalError msg
