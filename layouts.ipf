#pragma TextEncoding = "UTF-8" 
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

//Menu options for bringing windows in a layout to the front of the view (CTRL+1)
//optionally leaving other windows as is (CTRL+SHIFT+1). Default is to hide other windows.
//hideableWinTypes in layout_objToTop() sets what window types are hidden by the default action (currently, procedure windows are unaffected, for example)
//not certain of behavior for windows embedded in a layout, seems to ignore them, which is good
Menu "Layout"
	Submenu "Window control"
		"Show Layout Page Objects/O1",/Q,layout_objsToTop(0,0)		//currently running this with a blank layout page will minimize everything; could set up to ignore instead
		"Show Layout Page Objects and Hide Others/1",/Q,layout_objsToTop(1,0)
		
		//Would like to increment layout page number by +1 / -1 (with a single keyboard action) show layout objects
		//currently can't use programming to change layout page or get info about any page that is not the current page
		//Also currently window hooks don't respond to changes in layout page, which would be another way to implement this (e.g., shift during page change brings up graphs on that page)
		//	"Show Next Layout Page Objects/3",/Q,layout_objsToTop(1,1)	
		//	"Show Prev Layout Page Objects/2",/Q,layout_objsToTop(1,-1)	
	end
end

//These constants set the types of windows that can be appended to a layout from by these procedures
//in the future, probably better to make a function that gives the window type name for a window type number (the name is needed by appendLayoutObject)
//currently, this is error prone if these constants are incorrect
static strconstant ks_layoutAppendableWins = "graph;table;gizmo;"		//names of desired window types (semi-colon delimited)
static strconstant ks_layoutAppendableWinTypes = "1;2;65536;"	//window type numbers, ordered as for ks_layoutAppendableWins. Types defined in winList

//This constant sets the types of windows that could be hidden when bringing up windows on a layout page
static strconstant ks_layoutHideableWinTypes = "1;2;16;64;16384;65536;" //window type numbers specifying the window types to be minimized by layout_objsToTop. Types defined in winList

//appends windows (currently graphs, tables, gizmos) to a layout
//a future version could attempt to recapitulate the arrangement of the windows on the screen within the layout page (and possibly make layout pages that screen aspect ratio)
function/S layout_appendWinsToLayout(layoutName,page,winMatchStr,numWins)
	String layoutName		//name of layout to append windows to, or "" for top layout
	String winMatchStr	//match string for windows to append to layout, or "" for all (defaults to "*")
	int page		//page on layout to use, or NaN for current top page -- currently no handling for out of range pages (but UI options default to current page)
	int numWins	//number of windows to append
	
	if (strlen(layoutName) < 1)		//use top layout or create a layout if none exist
		String layouts = winlist("*",";","WIN:3")
		if (itemsinlist(layouts) == 0)
			newLayout/n=$layoutName
			layoutName = S_name
		else
			layoutName = stringfromlist(0,layouts)
		endif
	endif
	
	if (numtype(page))
		page=layout_getLayoutInfoAsNum(layoutName,"CURRENTPAGENUM")	//second parameter is defined in LayoutInfo
	endif

	if (strlen(winMatchStr) < 1)
		winMatchStr ="*"
	endif
	
	Variable winTypesBitwise = layout_getWinTypesBitwise(0)		//get layout-appendable win types (set by ks_layoutAppendableWinTypes)
	String name,wins=winlist(winMatchStr,";","WIN:"+num2str(winTypesBitwise)),typeStr,typeNameStr
	int i,num=min(numWins,itemsinlist(wins))
	Variable type
	
	for (i=0;i<num;i+=1)
		name=stringfromlisT(i,wins)
		type=wintype(name)
		type = 2^(type-1)		//convert from winType bitwise number to winList number
		typeStr = num2str(type)
		typeNameStr=stringfromlist(whichlistitem(typeStr,ks_layoutAppendableWinTypes),ks_layoutAppendableWins)
		appendlayoutobject/W=$layoutName/PAGE=(page) $typeNameStr $name
	endfor
	
	return layoutName
end

//menu options to append the window to a layout
//in future, could find a way to build in page options (currently defaults to current page)
menu "Windows",dynamic
	submenu "Append To Layout"
		layout_getLayoutMenuOptionsStr(),/Q,layout_appendWinToLayoutFromMenu()
	end
end

menu "GraphPopup", dynamic
	submenu "Append To Layout"
		layout_getLayoutMenuOptionsStr(),/Q,layout_appendWinToLayoutFromMenu()	//this assumes the graph that triggered the GraphPop is the top window.. could add a check that graphs are appendable
	end
End

function/s layout_getLayoutMenuOptionsStr()
	return winlist("*",";","WIN:4")+"~Create New Layout~;~Append Multiple Wins to Top Layout~;~Append Multiple Wins to New Layout~;"
end

//in the future, could allow filtering for window types
//as well as directing to specific layout pages
function layout_appendWinToLayoutFromMenu()

	getlastusermenuinfo
	String layoutName; Variable numWindowsToAppend = 1,page=nan
	
	
	if (Stringmatch(S_value,"~Append Multiple *~")) //handle options requiring prompt "~Multipe Windows~" and "~Multipe Windows & New Layout~". not sure if a complex window name could cause trouble here? Probably faster and more robust to check if selected index greater than number of layouts available
		
		prompt numWindowsToAppend, "Enter number of windows to append"
		
		String helpStr = "Append the specified number of windows (of types="+ks_layoutAppendableWins+") to the "		//helpStr completed in if statement
		
		if (Stringmatch(s_Value,"*to New Layout*"))
			helpStr += "new layout"
			layoutName = UniqueName("Layout", 8, 0)
			prompt layoutName,"Name of new layout"
			doprompt/help=helpStr "Append Windows to New Layout",numWindowsToAppend,layoutName
			if (V_flag)		//handle user cancel prompt
				return 0
			endif			
			newlayout/n=$layoutName
			layoutName = S_name
		else
			helpStr += "top layout"
			layoutName = winname(0,4)
			variable maxPageNum = layout_getLayoutInfoAsNum(layoutName,"NUMPAGES") //one indexed, not zero
			page = layout_getLayoutInfoAsNum(layoutName,"CURRENTPAGENUM") //one indexed, not zero
			prompt page,"Enter layout page number to append to (or leave as NaN for current page. Accpetable range=[1-"+num2str(maxPageNum)+"]"	//inclusive range
			doprompt/help=helpStr "Append Windows to Top Layout ("+layoutName+")",numWindowsToAppend,page
			if (V_flag)		//handle user cancel prompt
				return 0
			endif
			page = constrain(page,1,maxPageNum)		//assume user wants 0 if negative, last page if out of current page range. In future, could add pages
		endif

		
	else   //handle options where a layout was specified, or "New Layout" only, which doesnt prompt for the layout name (since it's not prompting for numWindows)
		
		if (StringMatch(S_Value,"~Create New Layout~"))
			newlayout
			layoutName=S_name
		else
			layoutName=S_value
		endif
	endif
	
	layout_appendWinsToLayout(layoutName,0,"",numWindowsToAppend)
	doupdate
end

//show the windows in the top layout, optionally hiding others
function layout_objsToTop(hideOthers,pageIncrement)
	int hideOthers		//if true, hide hideable window types that are not on layout page to be displayed
	int pageIncrement	//optionally increment (1) or decrement (-1) the current layout page before changing displayed windows
	
	if (!numtype(pageIncrement) && (pageIncrement != 0) )		//check whether layout page needs to be incremented
		String layoutName = winname(0,4)	//top layout
		int page=layout_getLayoutInfoAsNum(layoutName,"CURRENTPAGENUM")	//second parameter is defined in LayoutInfo. page numbers are indexed
		int maxPageNum = layout_getLayoutInfoAsNum(layoutName,"NUMPAGES") //one indexed, not zero
		page += pageIncrement
		page = wrapIndex(page-1,maxPageNum)+1	//wrap around in positive or negative direction, dealing with 1 vs 0 indexing
		
		//I don't think there is a ModifyLayout page=page parameter, so this is a workaround
		
	endif
	
	Variable k_hideableWinTypes = layout_getWinTypesBitwise(1)		//get bitwise variable for the types of hideable windows (set by ks_layoutHideableWinTypes)												

	
	String objs = layout_getPageObjList(""),name
	int numToShow=itemsinlist(objs),i
	
	if (hideOthers)
		String wins = winlist("*",";","WIN:"+num2str(k_hideableWinTypes))
		int numWins = itemsinlist(wins)
		for (i=0;i<numWins;i+=1)
			name = stringfromlist(i,wins)
			if (whichlistitem(name,objs) < 1)
				dowindow/hide=1 $name
			endif
		endfor
	endif
	
	for (i=0;i<numToShow;i+=1)
		name = stringfromlist(i,objs)
		dowindow/f/hide=0 $name
	endfor
end

function/s layout_getPageObjList(layoutName)
	String layoutName
	
	int i,numObjs = layout_getLayoutInfoAsNum(layoutName,"NUMOBJECTS")
	STring out = "",info,name
	for (i=0;i<numObjs;i+=1)
		info = layoutinfo(layoutName,num2str(i))
		name = stringbykey("name",info)
		out += name + ";"
	endfor	
	return out
end

function layout_getLayoutInfoAsNum(layoutName,keyStr)
	String layoutName,keyStr
	
	String info = layoutinfo(layoutName,"Layout")
	String listStr = stringbykey(keyStr,info)
	return str2num(listSTr)
end

//in the future, for speed, these could be calculated on the first call and stored somewhere (or precalculated in a constant by the user)
function layout_getWinTypesBitwise(hideableNotAppendable)
	int hideableNotAppendable		//0 for appendable win types (bitwise), 1 for hideable win types
	
	String bitList = selectstring(hideableNotAppendable,ks_layoutAppendableWinTypes,ks_layoutHideableWinTypes)
	Variable out = 0,i,num=itemsinlist(bitList)
	for (i=0;i<num;i++)
		out += str2num(stringfromlist(i,bitList))
	endfor
	return out
end

Menu "GraphPopup", dynamic
	submenu "Append To Layout"
		winlist("*",";","WIN:4")+"~Make New Layout~;",layout_appendWinToLayoutFromPopup()
	end
End

function layout_appendWinToLayoutFromPopup()
	getlastusermenuinfo
	String layoutN
	if (StringMatch(S_Value,"~Make New Layout~"))
		newlayout
		layoutN=S_name
	else
		layoutN=S_value
	endif
	
	layout_appendWinsToLayout(layoutN,0,S_graphName,1)
	doupdate
end