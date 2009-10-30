{-# OPTIONS_GHC -XScopedTypeVariables -XTypeSynonymInstances -XMultiParamTypeClasses -XDeriveDataTypeable #-}
-----------------------------------------------------------------------------
--
-- Module      :  IDE.Pane.Workspace
-- Copyright   :  2007-2009 Juergen Nicklisch-Franken, Hamish Mackenzie
-- License     :  GPL
--
-- Maintainer  :  maintainer@leksah.org
-- Stability   :  provisional
-- Portability :
--
-- |
--
-----------------------------------------------------------------------------

module IDE.Pane.Workspace (
    WorkspaceState
,   IDEWorkspace
,   updateWorkspace
,   getWorkspace
) where

import Graphics.UI.Gtk hiding (get)
import Graphics.UI.Gtk.Gdk.Events
import Data.Maybe
import Control.Monad.Reader
import Data.List
import Data.Typeable
import IDE.Core.State
import IDE.Workspaces
import Debug.Trace (trace)


-- | Workspace pane state
--

data IDEWorkspace   =   IDEWorkspace {
    scrolledView        ::   ScrolledWindow
,   treeViewC           ::   TreeView
,   workspaceStore      ::   ListStore (Bool,IDEPackage)
,   wsEntry             ::   Entry
,   topBox              ::   VBox
} deriving Typeable

instance Pane IDEWorkspace IDEM
    where
    primPaneName _  =   "Workspace"
    getAddedIndex _ =   0
    getTopWidget    =   castToWidget . topBox
    paneId b        =   "*Workspace"

-- | Nothing to remember here, everything comes from the IDE state
data WorkspaceState           =   WorkspaceState
    deriving(Eq,Ord,Read,Show,Typeable)

instance RecoverablePane IDEWorkspace WorkspaceState IDEM where
    saveState p     =   do
        return (Just WorkspaceState)
    recoverState pp WorkspaceState =   do
        nb      <-  getNotebook pp
        buildPane pp nb builder
    buildPane pp nb builder  =   do
        res <- buildThisPane pp nb builder
        when (isJust res) updateWorkspace
        return res
    builder pp nb windows = reifyIDE $ \ideR -> do
        listStore   <-  listStoreNew []
        treeView    <-  treeViewNew
        treeViewSetModel treeView listStore

        renderer0    <- cellRendererPixbufNew
        col0        <- treeViewColumnNew
        treeViewColumnSetTitle col0 "Active"
        treeViewColumnSetSizing col0 TreeViewColumnAutosize
        treeViewColumnSetResizable col0 True
        treeViewColumnSetReorderable col0 True
        treeViewAppendColumn treeView col0
        cellLayoutPackStart col0 renderer0 True
        cellLayoutSetAttributes col0 renderer0 listStore
            $ \row -> [cellPixbufStockId  :=
                        if (\(b,_)-> b) row
                            then stockYes
                            else ""]

        renderer1   <- cellRendererTextNew
        col1        <- treeViewColumnNew
        treeViewColumnSetTitle col1 "Package"
        treeViewColumnSetSizing col1 TreeViewColumnAutosize
        treeViewColumnSetResizable col1 True
        treeViewColumnSetReorderable col1 True
        treeViewAppendColumn treeView col1
        cellLayoutPackStart col1 renderer1 True
        cellLayoutSetAttributes col1 renderer1 listStore
            $ \row -> [ cellText := (\(_,pack)-> (fromPackageIdentifier . packageId) pack) row ]

        renderer2   <- cellRendererTextNew
        col2        <- treeViewColumnNew
        treeViewColumnSetTitle col2 "File path"
        treeViewColumnSetSizing col2 TreeViewColumnAutosize
        treeViewColumnSetResizable col2 True
        treeViewColumnSetReorderable col2 True
        treeViewAppendColumn treeView col2
        cellLayoutPackStart col2 renderer2 True
        cellLayoutSetAttributes col2 renderer2 listStore
            $ \row -> [ cellText := (\(_,pack)-> cabalFile pack) row ]

        treeViewSetHeadersVisible treeView True
        sel <- treeViewGetSelection treeView
        treeSelectionSetMode sel SelectionSingle

        sw <- scrolledWindowNew Nothing Nothing
        containerAdd sw treeView
        scrolledWindowSetPolicy sw PolicyAutomatic PolicyAutomatic
        entry           <-  entryNew
        set entry [ entryEditable := False ]
        box             <-  vBoxNew False 2
        boxPackStart box entry PackNatural 0
        boxPackEnd box sw PackGrow 0
        let workspacePane = IDEWorkspace sw treeView listStore entry box
        widgetShowAll box
        cid1 <- treeView `afterFocusIn`
            (\_ -> do reflectIDE (makeActive workspacePane) ideR ; return True)
        treeView `onButtonPress` (treeViewPopup ideR  workspacePane)
        return (Just workspacePane,[ConnectC cid1])

getWorkspace :: Maybe PanePath -> IDEM IDEWorkspace
getWorkspace Nothing = forceGetPane (Right "*Workspace")
getWorkspace (Just pp)  = forceGetPane (Left pp)

getSelectionTree ::  TreeView
    -> ListStore (Bool, IDEPackage)
    -> IO (Maybe (Bool, IDEPackage))
getSelectionTree treeView listStore = do
    treeSelection   <-  treeViewGetSelection treeView
    rows           <-  treeSelectionGetSelectedRows treeSelection
    case rows of
        [[n]]   ->  do
            val     <-  listStoreGetValue listStore n
            return (Just val)
        _       ->  return Nothing

treeViewPopup :: IDERef
    -> IDEWorkspace
    -> Event
    -> IO (Bool)
treeViewPopup ideR  workspacePane (Button _ click _ _ _ _ button _ _) = do
    if button == RightButton
        then do
            theMenu         <-  menuNew
            item1           <-  menuItemNewWithLabel "Activate Package"
            item2           <-  menuItemNewWithLabel "Add Package"
            item3           <-  menuItemNewWithLabel "Remove Package"
            item4           <-  menuItemNewWithLabel "Build Package"

            item1 `onActivateLeaf` do
                sel         <-  getSelectionTree (treeViewC workspacePane)
                                                (workspaceStore workspacePane)
                case sel of
                    Just (_,ideP)      -> reflectIDE (workspaceActivatePackage ideP) ideR

                    otherwise         -> return ()
            item2 `onActivateLeaf` reflectIDE workspaceAddPackage ideR
            item3 `onActivateLeaf` do
                sel            <-  getSelectionTree (treeViewC workspacePane)
                                                    (workspaceStore workspacePane)
                case sel of
                    Just (_,ideP)      -> reflectIDE (workspaceRemovePackage ideP) ideR
                    otherwise          -> return ()
            -- TODO ...
            menuShellAppend theMenu item1
            menuShellAppend theMenu item2
            menuShellAppend theMenu item3
            -- TODO ...
            menuPopup theMenu Nothing
            widgetShowAll theMenu
            return True
        else if button == LeftButton && click == DoubleClick
                then do sel         <-  getSelectionTree (treeViewC workspacePane)
                                            (workspaceStore workspacePane)
                        case sel of
                            Just (_,ideP)   ->  reflectIDE (workspaceActivatePackage ideP) ideR
                                                    >> return True
                            otherwise       ->  return False
                else return False
treeViewPopup _ _ _ = throwIDE "treeViewPopup wrong event type"

updateWorkspace :: IDEAction
updateWorkspace = do
    mbMod <- trace "update workspace called" getPane
    case mbMod of
        Nothing -> return ()
        Just (p :: IDEWorkspace)  -> do
            mbWs <- readIDE workspace
            case mbWs of
                Nothing -> liftIO $ do
                    listStoreClear (workspaceStore p)
                    entrySetText (wsEntry p) ""
                Just ws -> liftIO $ do
                    entrySetText (wsEntry p) (wsName ws)
                    listStoreClear (workspaceStore p)
                    let objs = map (\ ideP -> (Just ideP == wsActivePack ws, ideP)) (wsPackages ws)
                    mapM_ (listStoreAppend (workspaceStore p)) objs
