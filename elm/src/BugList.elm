-- Component showing a list of bugs


module BugList
    exposing
        ( Model
        , Filter
        , Msg(SelectBug)
        , init
        , subscriptions
        , update
        , view
        )

import Time
import Date
import Types exposing (..)
import ViewCommon exposing (..)
import Rest
import List.Extra exposing (groupWhile)
import Html exposing (..)
import Html.Events exposing (..)
import Html.Attributes exposing (..)
import Date exposing (Date)
import Date.Extra.Period as Period
import ChunkList exposing (ChunkList)
import RemoteData exposing (WebData)
import Task


type Msg
    = LoadedBugs Filter (WebData (Chunk Bug))
    | SelectBug (Maybe BugID)
    | LoadMoreBugs (Maybe Bug)
    | TimeTick Time.Time


type alias Filter =
    { environmentIDs : List EnvironmentID
    , includeClosed : Bool
    , search : String
    }


type alias Model =
    { filter : Filter
    , bugs : ChunkList Bug
    , selected : Maybe BugID
    , now : Date.Date
    }


init : Filter -> Maybe BugID -> ( Model, Cmd Msg )
init filter selected =
    ( { filter = filter
      , bugs = ChunkList.empty
      , selected = selected
      , now = (Date.fromTime 0)
      }
    , Cmd.batch
        [ fetchBugs filter Nothing
        , Task.perform TimeTick Time.now
        ]
    )



-- Subscriptions


subscriptions : Model -> Sub Msg
subscriptions model =
    Time.every Time.minute TimeTick



-- Updates


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LoadedBugs filter result ->
            -- TODO: clear selected bug if it's not in the list
            noCmd
                (if filter == model.filter then
                    { model | bugs = (ChunkList.update model.bugs result) }
                 else
                    model
                )

        LoadMoreBugs start ->
            ( model, fetchBugs model.filter start )

        TimeTick time ->
            noCmd { model | now = (Date.fromTime time) }

        SelectBug bugID ->
            noCmd { model | selected = bugID }


fetchBugs : Filter -> Maybe Bug -> Cmd Msg
fetchBugs filter start =
    Rest.fetch (LoadedBugs filter)
        (Rest.loadBugs
            filter.environmentIDs
            filter.includeClosed
            (Maybe.map .id start)
            filter.search
        )



-- FIXME: put somewhere common


noCmd : model -> ( model, Cmd Msg )
noCmd model =
    ( model, Cmd.none )


allBugs : Model -> List Bug
allBugs model =
    ChunkList.items model.bugs


view : Model -> Html Msg
view model =
    div [ class "sidebar-bugs menu" ]
        [ paginatedChunkList (sidebarBugGroups model) model.bugs LoadMoreBugs ]


sidebarBugGroups : Model -> List Bug -> List (Html Msg)
sidebarBugGroups model bugs =
    List.concatMap (sidebarBugGroup model) (bugGroups model.now bugs)


sidebarBugGroup : Model -> ( String, List Bug ) -> List (Html Msg)
sidebarBugGroup model ( label, bugs ) =
    if List.length bugs > 0 then
        [ h3 [ class "menu-label" ] [ text label ]
        , div [ class "sidebar-bug-group box" ] (List.map (sidebarBug model) bugs)
        ]
    else
        []


linkedIssues : Bug -> Html Msg
linkedIssues bug =
    span [] (List.map issueHref bug.issues)


issueHref : Issue -> Html Msg
issueHref issue =
    a [ href issue.url, class "is-warning tag" ] [ text (issueTitle issue) ]


sidebarBug : Model -> Bug -> Html Msg
sidebarBug model bug =
    let
        issueTag =
            linkedIssues bug

        isSelected =
            model.selected == Just bug.id

        clickMsg =
            SelectBug (Just bug.id)

        bugIsClosed =
            Maybe.withDefault False <| Maybe.map (always True) bug.closedAt

        occurrenceCountTag =
            span [ class "tag", classList [ ( "is-danger", bugIsClosed ) ] ] [ text (toString bug.occurrenceCount) ]
    in
        a
            [ class "sidebar-bug"
            , classList
                [ ( "is-active"
                  , isSelected
                  )
                ]
            , onClick clickMsg
            ]
            [ div
                [ class "sidebar-bug-title"
                ]
                [ h4 [ class "title is-6" ]
                    [ text (bugErrorClass bug)
                    ]
                , p [ class "subtitle is-6" ]
                    [ text (bugErrorMessage bug)
                    ]
                ]
            , div
                [ class
                    "sidebar-bug-tags"
                ]
                [ occurrenceCountTag
                , issueTag
                ]
            ]


bugGroups : Date.Date -> List Bug -> List ( String, List Bug )
bugGroups now bugs =
    let
        groupFor bug =
            let
                diff =
                    Period.diff now bug.lastOccurredAt
            in
                if diff.week >= 1 then
                    "Earlier"
                else if diff.day >= 1 then
                    "Past Week"
                else if diff.hour >= 1 then
                    "Past Day"
                else
                    "Past Hour"

        flattenGroup grouped =
            case grouped of
                ( g, b ) :: rest ->
                    ( g, List.map Tuple.second grouped )

                [] ->
                    ( "Grouping error", [] )
    in
        bugs
            |> List.map (\bug -> ( groupFor bug, bug ))
            |> groupWhile (\a b -> Tuple.first a == Tuple.first b)
            |> List.map flattenGroup
