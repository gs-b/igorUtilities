#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

menu "Macros"
	"tracing_setZoom/4"
end

Menu "GraphMarquee"
	"Expand at fixed ratio (for tracing)", marquee_expandAtFixedRatio()
End	

function tracing_setZoom()
	NVAR/Z tracing_followSubRegZoom
	if (!Nvar_exists(tracing_followSubRegZoom))
		Variable/G tracing_followSubRegZoom
	endif
	print "tracing_setzoom() running: tracing_followSubRegZoom = 2"
	Execute "tracing_followSubRegZoom = 2"
	putscraptext "tracing_followSubRegZoom = 6"
end


function img_hook(s)
	STRUCT WMWinHookStruct &s		//
	
	Variable actionType = 0		//default will be actionType = 0 causing a return, having done nothing
	
	
	//new action type added 170613 .. the whole actionType thing is a bit circuitous but it's where we're at...
	//keyCode 13 is enter down. eventmod 2 is alt; so alt+ enter will copy in last radius; keycode 11 and 12 are page up and down.. used to copy over previous or next point radius
	if ( ((s.keyCode == 13) && (s.eventmod & 2^2) ) || (s.keyCode == 11) || (s.keyCode == 12) ) 
		actionType = 3	
	elseif	( ((s.eventCode == 22) || (s.eventCode == 3)) || (s.keyCode == 13) ) //22 is mouseWheel, 3 is mouse down, keyCode 13 is enter down. So only continue for mouse wheel, mouse down, OR enter
	//	if ( ((s.eventCode == 22) || (s.eventCode == 3)) || (s.keyCode == 13) )		//changed to if elseif 170613
		actionType = 1
	endif
	
	//handles follow with ctrl + left/right arrow key
	if ( (s.keycode == 28) || (s.keycode == 29) )
		actiontype = 2
	endif
	//handles cross section sizer change with ctrl + up/down arrow key
	//do cross section update -- handles wheel scrolling and arrow up/down with ctrl key (and shift modification for coarse/fine
	Variable keyEventHandling = tracing_updatesCrossSect(s)
	
	if (!actionType)
		return keyEventHandling
	endif
	
	//170613 added actionType 3 to support updating of selecting point to a new radius
	//most useful is page up or page down (no longer requires alt) which stores the radius of the preceding point (down) or next point (up) for this point
	//use alt + left right arrow to move through points
	//then use ctrl + scroll with or without shift (which gives a coarser modulation) to set radius measurement circle
	//then hit alt + enter to store the new radius for this point
	
	if (actionType == 3)
		switch (s.keyCode)
			case 13:		//enter key, just store this points value
				//tracing_setCurrCrossSectSize(winN,nan,asIncrement)
				break
			case 11:
				tracing_setCurrCrossSectSize(s.winname,nan,1)
				//tracing_storeZValueForCurrPnt(s.winname,useValFromDelta=1)		//replaced by above
				break
			case 12:
				tracing_setCurrCrossSectSize(s.winname,nan,-1)	
				//tracing_storeZValueForCurrPnt(s.winname,useValFromDelta=-1)	//replaced by above
				break
		endswitch
		return 1		//return one lets Igor know not to use this key event, which would normally bring up the command line
	endif

		
	//actionType = 1 handles commands related to actually adding and removing points
	if (actionType == 1)
	//starts or continues tracing by adding the first or an additional new point
		if ( (s.eventCode == 3) && ( (s.eventMod & 2^3) != 0) || ((s.eventMod & 2^1) != 0) )			// click with control button down
			//tracing_saveCrossSectLastInWv()		//obsolete		//allows previous point to be saved. also called when a new section is being created to catch the last point
			tracing_addPointFromClickLoc(s)
			return keyEventHandling
		endif
		
		if (s.keyCode == 13)		//enter, allow duplicate entry of last point added
			//tracing_saveCrossSectLastInWv()		//obsolete
			tracing_repeatPoint(s.winName)
			return keyEventHandling
		endif
		
		img_scroll(s)		//scroll control
		tracing_doUpdates(s.winname,nan,nan,nan)
	endif
	
//	Print s.eventcode, s.eventmod
	
	//actionType == 2 or other things also going with actionType == 1
	//these handle 
	//170613 changed to using control key not alt key + arrows to move
	//2^3 is ctrl, keyCode 28 and 29 are left and right arrow key... so this handles what to do with left/right arrow key
//	if ( (s.eventmod & 2^3) && ( (s.keycode == 28) || (s.keycode == 29) ) )			//(s.eventCode == 22) )	
	if  ( (s.keycode == 28) || (s.keycode == 29) ) 	
		Variable follow_wheelMult = 3		//for some reason -3 and 3 are s.wheeldx vals
		tracing_follow(s.winname,nan,	s.keycode-28 == 0 ? -1 : 1,1)		//s.wheelDx/follow_wheelMult,1)
		return 1		//return one lets Igor know not to use this key event, which would normally bring up the command line
	endif
	
	//img_updateOrthoViews(s)
end


function img_newImage(imgWvRef, promptNewLoad, useFileName)
	String imgWvRef
	Variable promptNewLoad		//0 to display an image already in imgWvRef, 1 to prompt loading of a new image (img will be stored in imgWvRef, if ref is passed)
	Variable useFileName	//use loaded file name for wave name
	
	Variable decentInchesPerPixelForMyTiffs = 0.01
	
	if (promptNewLoad)
		img_loadImage(imgWvRef,useFileName)
	endif
	
	if (!waveexists($imgWvRef))
		Print "img_newImage() no image found, aborting. (perhaps wave load was aborted?)"
		return 0
	endif
	
	if (dimsize($imgWvRef,2) < 1)
		Print "img_newImage() adding layer to 3rd dimension for tracing compatibility."
		redimension/n=(-1,-1,2) $imgWvRef
	endif
	
	NewImage/K=1 $imgWvRef
	String winN = S_name
	doupdate;
	SetWindow $winN, userdata=imgWvRef		//store name of displayed image in userdata
	doupdate;
	img_addHook()
	doupdate;
	img_fixedSizeAtAspectRatio(winN, imgWvRef, decentInchesPerPixelForMyTiffs)
	img_addZoomHook()
	
	//add slider (code from menu defitions in WMMenus.ipf that shipped with Igor 7). Error does still occur
	Execute/P/Q/Z "INSERTINCLUDE <ImageSlider>";Execute/P/Q/Z "COMPILEPROCEDURES ";Execute/P/Q/Z "WMAppend3DImageSlider()"
	

	Print "run: img_updateHist(1, 0)"
end

//load an image with Igor's ImageLoad. Works well for Tiff Stacks and probably not much else. 
//pass imgWvRef,a ref into which the image will be saved (overwrites this destination)
function/S img_loadImage(imgWvRef,useFileName)
	String imgWvRef; variable useFileName
	
	if (useFileName)
		imgWvRef="img_loadImageTemp"
	endif
	
	if (strlen(imgWvRef) < 1)		//no name passed, get used to make it
		prompt imgWvRef, "Enter reference name into which image will be saved"
		doprompt "Image name:", imgWvRef
	endif
	
	ImageLoad/O/S=0/C=-1/LR3D/N=$imgWvRef/p=home
	if (V_flag)		//load successful
		if (useFileName)
			string out=replacestring(".",S_fileName,"_")[0,31]	//make extension into acceptable string and truncate if needed
			duplicate/o $imgWvRef,$out		
			if (strlen(S_fileName) > 31)
				Print "img_loadImage: fileName",s_fileName,"is too long and being truncated to wavename",out
			endif
		endif
		note/nocr $imgWvRef, "img_loadPath:"+S_path+";"
		return S_path
	endif
	
	return ""//load failed if reached here
end

function/S img_setImageLoadPath(imgWvRef)
	String imgWvRef
	
	String appendStr = "forPathTemp"		//append string so that image is not overwritten
	
	String path = img_loadimage(imgWvRef + appendStr,0)
	
	note/nocr $imgWvRef, "img_loadPath:"+path+";"

	killwaves/Z $(imgWvRef + appendStr)
	return path
end

function img_addHook()
	setwindow $"" hook(scrollAndTraceHook) = img_hook
end
function img_addZoomHook()
	setwindow $"" hook(zoomHook) = img_zoomHook
end
function img_fixedSizeAtAspectRatio(winN, imgWvName, inchesPerPixel)
	Variable inchesPerPixel
	String winN, imgWvName
	
	Variable decentInchesPerPixelForMyTiffs = 0.01		//only used if inchesPerPixel not passed
	
	if (numtype(inchesPerPixel) > 0)		//NaN or +/-inf
		inchesPerPixel = decentInchesPerPixelForMyTiffs
	endif
	
	Variable arbUnitPerInch = 72
	
	if (strlen(winN) < 1)
		winN = winname(0,1)
	endif
	
	if (strlen(imgWvName) < 1)
		imgWvName = stringfromlist(0,wavelist("*",";","WIN:"+winN))
	endif
	
	Variable xPixels = DimSize($imgWvName,0)
	Variable yPixels = DimSize($imgWvName,1)
	
	Variable w = arbUnitPerInch*xPixels*inchesPerPixel
	Variable h = arbUnitPerInch*yPixels*inchesPerPixel
	
	ModifyGraph/W=$winN width=w, height=h
	
end

function img_updateOrthoViews(s) 
	STRUCT WMWinHookStruct &s
	
	String images = ImageNameList(s.winname,";" )
	
	Variable leftLoc=disp_getMouseLoc(s,"left")
	Variable topLoc=disp_getMouseLoc(s,"top")
	
	Variable i,num=itemsinlist(images)
	String pzRef,zqRef,imgRef,pzWin,zqWin
	
	//check that waves exist
	for (i=0;i<num;i+=1)
		imgRef=stringfromlist(i,images)
		//standard is p,q,r as y,x,z
		pzRef=imgRef+"pz" //p vs z with q in layers, equiv y vs z with x in layers -- swap for [p][r][q] 
		zqRef=imgRef+"zq" //z vs q with 	p in layers, equiv z vs x with y in layers -- swap for [r][q][p]
		pzWin=pzRef+"W"
		zqWin=zqRef+"W"
		if (!WAveExists($pzRef))
			//for xz need y to go into layers and z to go into rows
			imagetransform/g=1 transposeVol $imgRef   		//[p][r][q] 
			WAVE M_VolumeTranspose
			duplicate/o M_VolumeTranspose $pzRef
		endif
		if (!WaveExists($zqRef))
			imagetransform/g=3 transposeVol $imgRef   		//[r][q][p]
			WAVE M_VolumeTranspose
			duplicate/o M_VolumeTranspose,$zqRef
		endif
		if (Wintype(pzWin)==0)
			newimage/k=1/n=$pzWin $pzRef
		endif
		if (Wintype(zqWin)==0)
			newimage/k=1/n=$zqWin $zqRef
		endif	
		
		if (numtype(leftLoc)==0)		//find x (q) position and show it's layer
			ModifyImage/W=$pzWin $pzRef plane=leftLoc
		else
			print "A"
		endif	
		
		if (numtype(topLoc)==0)		//find y (p) position and show it's layer
			ModifyImage/W=$zqWin $zqRef plane=topLoc
		else
			print "B"
		endif
	endfor
	
end

function tracing_follow(winN,goToPnt,deltaFromCurrPnt,doSetZ)
	String winN
	Variable goToPnt		//pass nan to use deltaFromCurrPnt
	Variable deltaFromCurrPnt	//ignored if goToPnt is not NaN
	Variable doSetZ		//pass to set z to the goToPnt's z location
	
	String followSubRegZoomVarName = "tracing_followSubRegZoom"		//string is empty or non-existant for no following
																				//for following it's "x;y;" where x is multiplier/zoom factor in x and y in y
	
	Variable autoStoreChangesInCrossSect = 1
	
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D/Z combinedSegWv = $combinedSegRef
	
	if (!WaveExistS(combinedSegWv))
		return 0
	endif

	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	Variable totalNumPnts = dimsizE(combinedSegWv,0)		//in all segs
	Variable currPnt,newPnt,usesDelta
	
	if (numtype(goToPnt) == 2)	//nan -- use delta
		currPnt = tracing_getSelPntData(winN,nan)
		newPnt = currPnt + deltaFromCurrPnt
		usesDelta = 1
	else
		newPnt = goToPnt
		usesDelta = 0
	endif
	
	newPnt = tracing_truncPntValueIfNeeded(newPnt,winN)
	
	if (newPnt == inf)	//only likely with goToPnt
		newPnt = totalNumPnts - 1
	elseif (newPnt == -inf)
		newPnt = 0
	elseif (newPnt < 0)
		newPnt = totalNumPnts + newPnt		//should wrap around to positive
	elseif (newPnt >= totalNumPnts)
		newPnt = mod(newPnt,totalNumPnts)	//should also wrap around
	endif		//leave newPnt unchanged if a real number that is in 0 and totalNumPnts -1

	String segLabel = 	GetDimLabel(combinedSegWv, 0, newPnt)
	
	if (!strlen(segLabel))
		return 0
	endif
	
	Variable segNum = tracing_segNumFromSegRef(segLabel)
	Variable segPntNum = tracing_getSegPntFromSegRef(segLabel)
	String lastSegLabel = GetDimLabel(combinedSegWv, 0, currPnt)
	Variable lastSegNum = tracing_segNumFromSegRef(lastSegLabel)
	Variable lastSegPntNum = tracing_getSegPntFromSegRef(lastSegLabel)
	//for delta, try to update cross sect wave
	if (autoStoreChangesInCrossSect && usesDelta)
	//this became unnecessary once oval was used for drawing
	//	tracing_storeZValueForCurrPnt(winN)		//store the current size shown for that last point
	endif
	
	//change plane to that of newly selected point
	if (doSetZ)
		Variable zPixLoc = combinedSegWv[newPnt][%zPixLoc]
	
		img_setDisplayedPlane(winN, zPixLoc)
	endif
	
	//update displayed points (e.g., shape and size) which should highlight new point and segment
	tracing_setSelPntData(newPnt,winN)		//170613 changed this to precede tracing_doUpdates call, as wasn't seeing point highlighting
	tracing_doUpdates(winN,segPntNum,segNum,segPntNum)
	String combinedSegTableN = tracing_getCombinedSegRefTableN(combinedSegRef)
	if (wintype(combinedSegTableN))
		//go to region of pnt on table
		Modifytable/W=$combinedSegTableN topleftcell = (newPnt-5,0)
		modifytable/W=$combinedSegTableN selection=(newPnt,0,newPnt,dimsize(combinedSegWv,1),newPnt,0)
	endif
	
	NVAR/Z followSubRegZoom = $followSubRegZoomVarName
	if (NVAR_Exists(followSubRegZoom) && (numtype(followSubRegZoom)==0) && followSubRegZoom > 1)
		WAVE traceWv = $tracedWaveName
		Variable xNativeRange = dimsize(traceWv,0)
		Variable yNativeRange = dimsize(traceWv,1)
		Variable maxNativeRange = max(xNativeRange,yNativeRange)
		Variable xIsMaxNativeRange = xNativeRange >= yNativeRange
		Variable range = maxNativeRange / followSubRegZoom
		Variable xCenterPos = combinedSegWv[newPnt][%xPixLoc]
		Variable xRangeStart = xCenterPos - range/2
		Variable xRangeEnd = xCenterPos + range
		Variable yCenterPos = combinedSegWv[newPnt][%yPixLoc]
		Variable yRangeStart = yCenterPos - range/2
		Variable yRangeEnd = yCenterPos + range
		//user should check that graph is square
		setaxis/w=$winN top xRangestart,xRangeEnd
		setaxis/w=$winN left yRangeEnd,yRangeStart	//y axis usually flipped
		modifygraph/w=$winN width=72*7,height=72*7;doupdate
		modifygraph/w=$winN width=0,height=0
	endif
	
//	Variable autoRadiusPerformed=str2num(GetUserData(winN,"", "autoRadiusPerformed" ))
//	if (autoRadiusPerformed)
//		String autoRadiusDispWin=winN+"ARD"
//		
//		Variable newGraph
//		if (wintype(autoRadiusDispWin) < 1)
//			display/k=1/n=$autoRadiusDispWin
//			String crossSectXYWvRef=tracing_getCrossSectXYWvRef()
//			appendtograph/l=left2/b=bottom2/w=$autoRadiusDispWin $combinedSegRef[][%radiusPix]
//			appendtograph/l=left2/b=bottom2/w=$autoRadiusDispWin $crossSectXYWvRef[][6] vs $crossSectXYWvRef[][7]
//			ModifyGraph/w=$autoRadiusDispWin marker=19,mode($crossSectXYWvRef)=3
//			ModifyGraph/w=$autoRadiusDispWin mode($combinedSegRef)=4,msize($combinedSegRef)=1,lsize($combinedSegRef)=1,rgb($combinedSegRef)=(0,0,0)
//			dowindow/f $winN
//		endif
//		
//		String traceNames=tracenamelist(autoRadiusDispWin,";",1)
//		
//		String interpRef=winN+ "ORTHO"
//		String interpFitRef=winN+"ORTHOF"
//		String interpXVals="winN"+"ORTHOX"
//		String interpYVals="winN"+"ORTHOY"
//		String interpWidth="winN"+"ORTHOW"
//		
//		if (waveexists($interpRef))
//			if (whichlistitem(interpRef,traceNames) < 0 )
//				appendtograph/c=(0,0,0)/w=$autoRadiusDispWin $interpRef[][newPnt]
//			else
//				replacewave/w=$autoRadiusDispWin trace=$interpref, $interpRef[][newPnt]
//				modifygraph/w=$autoRadiusDispWin freepos=0,lblpos=50,axisEnab(bottom2)={0.53,1},axisEnab(bottom)={0,0.47},freePos(left2)={-8,bottom2}
//			endif
//		endif
//		if (waveexists($interpFitRef))
//			if (whichlistitem(interpFitRef,traceNames) < 0 )
//				appendtograph/w=$autoRadiusDispWin $interpFitRef[][newPnt]
//			else
//				replacewave/w=$autoRadiusDispWin trace=$interpFitRef, $interpFitRef[][newPnt]
//				modifygraph/w=$autoRadiusDispWin freepos=0,lblpos=50,axisEnab(bottom2)={0.53,1},axisEnab(bottom)={0,0.47},freePos(left2)={-8,bottom2}
//			endif
//		endif
//		
//		String autoRadiusAllRef = combinedSegRef + "_rad"
//		if (WaveExists($autoRadiusAllRef))
//			variable plotStart=finddimlabel($autoRadiusAllRef, 1, "interpStart" )
//			if (whichlistitem(autoRadiusAllRef,traceNames) < 0 )
//				if (!WaveExists($"autoRadiusDispPlaceholder"))
//					make/o/n=2 autoRadiusDispPlaceholder
//					autoRadiusDispPlaceholder=0
//				endif
//				appendtograph/w=$autoRadiusDispWin/vert $autoRadiusAllRef[newPnt][plotStart,plotStart+1] vs $"autoRadiusDispPlaceholder"
//				modifygraph/w=$autoRadiusDispWin lsize($autoRadiusAllRef)=2,rgb($autoRadiusAllRef)=(52428,1,41942,45875)
//			else
//				replacewave/w=$autoRadiusDispWin trace=$autoRadiusAllRef,$autoRadiusAllRef[newPnt][plotStart,plotStart+1] 
//			endif	
//		endif
//		
//		WAVE interpX=$interpXVals
//		WAVE interpY=$interpYVals
//		WAVE tracing_interpxyvals
//		duplicate/o/r=[][newPnt] $interpWidth,interpWidthDisp
//		duplicate/o/r=[][newPnt] $interpRef,interpTest
//		duplicate/o/r=[][newPnt] interpX,tracing_interpxyvals
//		duplicate/o/r=[][newPnt]/free interpy,ytemp
//		concatenate/np=1 {ytemp},tracing_interpxyvals
//		//tracing_interpxyvals[][0] = interpX[p][newPnt]
//		//tracing_interpxyvals[][1] = interpY[p][newPnt]
//		
//		String tracingTraces=tracenamelist(winN,";",1)
//		
//			//interpolation display
////		if (whichlistitem("tracing_interpXYVals",tracingTraces) < 0)		//main interp xy val display
////			appendtograph/t/l/w=$winN tracing_interpXYVals[][1] vs tracing_interpXYVals[][0]
////			ModifyGraph/w=$winN lsize(tracing_interpXYVals)=2
////			ModifyGraph/w=$winN zColor(tracing_interpXYVals)={interpTest,*,*,BlueRedGreen,0}
////		endif
//		
//			//determined width/diameter display
////		if (whichlistitem("tracing_interpXYVals_width",tracingTraces) < 0)		//main interp xy val display
////			appendtograph/t/l/w=$winN tracing_interpXYVals[][1]/tn=tracing_interpXYVals_width vs tracing_interpXYVals[][0]
////			ModifyGraph/w=$winN lsize(tracing_interpXYVals_width)=2
////			ModifyGraph/w=$winN zColor(tracing_interpXYVals_width)={interpWidthDisp,0.5,2,Magenta,0},lsize(tracing_interpXYVals_width)=5,zcolorMin(tracing_interpXYVals_width)=nan
////			ModifyGraph/w=$winN rgb(tracing_currCrossSectXYPos)=(65535,0,0,13107)
////		endif	
//	endif

end//tracing_follow

//this implements wrapping around for pnt values, so one can increment and come back to the beginning of the row dimension for the combined wave of points
function tracing_truncPntValueIfNeeded(pntNum,winN)
	Variable pntNum
	String winN
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif

	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	
	Variable totalNumPnts = dimsizE($combinedSegRef,0)		//in all segs
		
	if (pntNum == inf)	//only likely with goToPnt
		pntNum = totalNumPnts - 1
	elseif (pntNum == -inf)
		pntNum = 0
	elseif (pntNum < 0)
		pntNum = totalNumPnts + pntNum		//should wrap around to positive
	elseif (pntNum >= totalNumPnts)
		pntNum = mod(pntNum,totalNumPnts)	//should also wrap around
	endif		//leave newPnt unchanged if a real number that is in 0 and totalNumPnts -1		
	
	return pntNum
	
end

function tracing_getSelPntData(winN,segNum)
	String winN
	Variable segNum		//if segNum is a real, valid seg num, then returns the row within the segment, if segNum is -1, returns row within current segment, if segNum is nan, returns the row of the pnt with in combiendSegref
							//actually right now it appears any real number just returns the point's row in its segment
	Variable pnt
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	String pntStr = GetUserData(winN, "", "tracing_follow_currPnt")
	if (!strlen(pntStr))		//likely no pnt set -- default to start at zero
		pnt = 0		//first point in order of all segments. make 0 to start at first pnt
		tracing_setSelPntData(pnt,winN)
	else
		pnt = str2num(pntStr)
		if (numtype(pnt) || (pnt < 0))
			pnt = 0
			tracing_setSelPntData(pnt,winN)
		endif
	endif 
	
	if (numtype(segNum))
		return pnt		//pnt is row within combinedSegRef
	else
		String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
		String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
		WAVE/D combinedSegWv = $combinedSegRef
		
		if (!strlen(combinedSegRef) || !WaveExistS(combinedSegWv))
			return 0
		endif
		
		String segLabel = 	GetDimLabel(combinedSegWv, 0, pnt )
		
		// "pntStr",pntStr,"pnt",pnt,"segLabel",segLabel
				
		if (!strlen(segLabel))
			return 0
		endif
		
	//	Variable segNum = tracing_segNumFromSegRef(segLabel)
		return tracing_getSegPntFromSegRef(segLabel)	
	endif
end

function tracing_setSelPntData(pnt,winN)
	String winN
	Variable pnt		//row in combined seg wave that is currently the selected / focused pnt
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	setwindow $winN, userdata(tracing_follow_currPnt) = num2str(pnt)	
	Variable/G tracing_follow_currPnt=pnt  //only used in case one wants to set up a dependency. probably things will run faster without this
end

function tracing_getCurrSegNum(winN)
	String winN
	
	SVAR/Z tracing_currTracingWaveName
	if (!svar_Exists(tracing_currTracingWaveName))
		String/G tracing_currTracingWaveName = ""
		return -1
	endif
	
	if (strlen(tracing_currTracingWaveName))
		String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
		String indexRef =  tracing_getTracingIndexWaveRef(tracedWaveName)
		WAVE/T indexWv = $indexRef
		Variable index = FindDimLabel(indexWv, 0, tracing_currTracingWaveName)
		if (index < 0)		//likely not found..one possibility is that dim labels aren't there
			Variable i
			for (i=0;i<DimSize(indexWv,0);i+=1)
				SetDimLabel 0,i,$indexWv[i][0],indexWv
			endfor
		endif
		return FindDimLabel($indexRef, 0, tracing_currTracingWaveName)		
	else
		return -1
	endif 
	
	return -1
end

function tracing_editAtSeg(winN,segNum)
	String winN
	Variable segNum		//segment number e.g. that in # _c#
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif

	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String indexRef =  tracing_getTracingIndexWaveRef(tracedWaveName)
	WAVE/T indexWv = $indexRef
	
	SVAR/Z tracing_currTracingWaveName
	if (!svar_Exists(tracing_currTracingWaveName))
		String/G tracing_currTracingWaveName
	endif
	
	Variable numSegs = dimsize(indexWv,0)
	if (segNum < 0)
		segNum = 0
	endif
	if (segNum > numSegs-1)
		segNum = numSegs - 1
	endif
	
	tracing_currTracingWaveName = indexWv[segNum][0]
	
	Print "tracing_editAtSegment(): tracing_currTracingWaveName",tracing_currTracingWaveName
	
end

//forces two segments to abut by inserting a new first point in the segment for segNum_post
//and settings this new first point to all the values of the point in the last segment
function tracing_makeSegsAbut(winN,segNum_pre,segNum_post[,noUpdates])
	variable segNum_pre,segNum_post		//pass NaN for segNum_pre to do all
	Variable noUpdates
	String winN//tracing winN
	if (!strlen(winN))
		winN = winname(0,1)
	endif

	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String indexRef =  tracing_getTracingIndexWaveRef(tracedWaveName)
	WAVE/T indexWv = $indexRef
	
	if (numtype(segNum_pre) > 0)	
		Variable i,numSegs = dimsize(indexWv,0)
		for (i=1;i<numSegs;i+=1)
			tracing_makesegsAbut(winN,i-1,i,noUpdates=1)
		endfor
		return 1
	endif
	
	WAVE/Z segWv_pre = $indexWv[segNum_pre][0]
	if (!WAveExists(segWv_pre))
		Print "tracing_makeSegsAbut(): pre segnemt",indexWv[segNum_pre][0],"not found, aborting"
		return 0
	endif
	WAVE/Z segWv_post = $indexWv[segNum_post][0]
	if (!WAveExists(segWv_post))
		Print "tracing_makeSegsAbut(): pre segnemt",indexWv[segNum_post][0],"not found, aborting"
		return 0
	endif
	
	InsertPoints/M=0 0, 1, segWv_post
	segWv_post[0][] = segWv_pre[DimSize(segWv_pre,0)-1][q]
	
	if (ParamIsDefault(noUpdates) || !noUpdates)
		tracing_doupdates(winN,nan,nan,nan)
		//(winN,currSegRow_forCrossSect,highlightedSeg,highlightedSegPnt)
	endif	
	
	return 1
end

function tracing_deleteSeg(winN,segNum)
	String winN		//name of tracing window or "" for top
	Variable segNum	
	
	//make the new segment wave
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String indexWvRef = tracing_getTracingIndexWaveRef(tracedwaveName)
	WAVE/T indexWv = $indexWvRef
	
	DeletePoints/M=0 segNum, 1, indexWv		//remove indexing of the combined waves, saving only the first
	
	//rename tracing segment waves based on shift in order
	Variable firstAffectedSeg = segNum,i,j,numPointsInSeg		//next segment is now at position of deleted seg
	Variable numSegs=dimsize(indexwv,0)
	String oldRef,newRef
	for (i=firstAffectedSeg;i<numSegs;i+=1)
		newRef = tracedWaveName + "_c" + num2str(i)		//name = [tracedWaveName]_c[row#]
		oldRef = indexWv[i][0]
		Duplicate/O $oldRef,$newRef		//cant use rename because wave may pre-exist and be in a window so it can't be killed
		killwaves/Z $oldRef		//might not be killed if were in window, e.g. as the current tracing wave gets displayed in a table
		indexWv[i][0] = newRef
		SetDimLabel 0,i,$newRef,indexWv
		
		//then update the row labels in the segment wave
		WAVE segWv = $newRef
		numPointsInSeg = dimsize(segWv,0)
		for (j=0;j<numPointsInSeg;j+=1)
			setdimlabel 0,j,$(newRef+"_"+num2str(j)),segWv
		endfor
	endfor
end


function tracing_combineSegs(winN,startSegNum,endSegNum,newSegName)
	String winN		//name of tracing window or "" for top
	Variable startSegNum	//first segment for combining -- seg nums are their row in the index (_ind) wave
	Variable endSegNum		//last segment for combining. segs must be contiguous,a common input would be start=3,end=4 to combine segs 3 and 4
	String newSegName		//new name for segment, e.g. if old segments were is and is1 or ax0,ax1,ax2 is or ax would be reasonable. pass "" to just use the name of the first segment

	
	//make the new segment wave
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String indexWvRef = tracing_getTracingIndexWaveRef(tracedwaveName)
	WAVE/T indexWv = $indexWvRef
	String firstSegRef = indexWv[startSegNum][0]		//all other waves are appended to this segment; its name doesn't need to change
	
	Variable maxSegNum = dimsize(indexWv,0)-1
	endSegNum = maxSegNum < endSegNum ? maxSegNum : endSegNum		//truncate end seg to last possible if needed
	
	Variable numSegs = endSegNum - startSegNum + 1
	if (numSegs < 2)
		return 0
	endif
	
	if (!strlen(newSegName))
		newSegName = indexWv[startSegNum][1]		//use the current name of the first segment if no segment is passed
	endif
	
	String nextSegRef
	Variable i, numCats = numSegs-1
	for (i=0;i<numCats;i+=1)
		nextSegRef = indexWv[startSegNum+1+i][0]
		concatenate/NP=0/Kill nextSegRef+";",	$firstSegRef
	endfor
	//row labels are fixed up automatically upon update via the call to tracing_showSegTable_ref
	
	//fix up the index wave
	indexWv[startSegNum][1] =  newSegName		//store the new name
	DeletePoints/M=0 startSegNum+1, numCats, indexWv		//remove indexing of the combined waves, saving only the first
	
	//rename tracing segment waves based on shift in order
	Variable newLastSegNum = dimsize(indexWv,0),j,numPointsInSeg
	String oldRef,newRef
	for (i=startSegNum+1;i<newLastSegNum;i+=1)
		newRef = tracedWaveName + "_c" + num2str(i)		//name = [tracedWaveName]_c[row#]
		oldRef = indexWv[i][0]
		Duplicate/O $oldRef,$newRef		//cant use rename because wave may pre-exist and be in a window so it can't be killed
		killwaves/Z $oldRef		//might not be killed if were in window, e.g. as the current tracing wave gets displayed in a table
		indexWv[i][0] = newRef
		SetDimLabel 0,i,$newRef,indexWv
		
		//then update the row labels in the segment wave
		WAVE segWv = $newRef
		numPointsInSeg = dimsize(segWv,0)
		for (j=0;j<numPointsInSeg;j+=1)
			setdimlabel 0,j,$(newRef+"_"+num2str(j)),segWv
		endfor
	endfor
	
	SVAR tracing_currTracingWaveName
	tracing_currTracingWaveName = indexWv[startSegNum][0]
	tracing_doUpdates(winN,nan,nan,nan)	
end

//ccPntNum will be the first point in the second of two segments created from one segment
function tracing_splitSeg(winN,ccPntNum,preSegName,postSegName)
	String winN
	Variable ccPntNum		//pass nan to use currently selected point on GUI
	String preSegName,postSegName		//name of new segments. pass "" for pre to use pre-existing name
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	if (numtype(ccPntNum))
		ccPntNum = tracing_getSelPntData(winN,nan)		//current selection
	endif

	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String indexWvRef = tracing_getTracingIndexWaveRef(tracedwaveName)
	WAVE/T indexWv = $indexWvRef
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D ccWv = $combinedSegRef
	String segLabel = 	GetDimLabel(ccwv, 0, ccPntNum)
	if (!strlen(segLabel))
		Print "tracing_interp(): could not find seg label! aborting"
		return 0
	endif
	Variable segNum = tracing_segNumFromSegRef(segLabel)
	Variable preSegNum = segNum, postSegNum = segNum+1, nextSegNum = segNum + 2
	Variable segPntNum = tracing_getSegPntFromSegRef(segLabel)
	String segRef = tracing_getSegNameForCCPnt(winN,ccPntNum)
	String origSegName = indexWv[segNum][1]
	WAVE segWv= $segRef
	if (!strlen(preSegName))
		preSegName = origSegName		//get the segment name
	endif
	
	//set the new names for the two new segments
	String preRef = tracedWaveName + "_c" + num2str(segNum)		//should be the same as original segRef, won't actually use this. just a sanity check in debug
	String postRef = tracedWaveName + "_c" + num2str(segNum+1)		//should be the same as original segRef
	
	//make room in the index wave for the new segment and update the index wave
	InsertPoints/M=0 postSegNum, 1,indexWv
	
		//give the new segments proper names
	indexWv[preSegNum][0] = preRef
	indexWv[postSegNum][0] = postRef
	indexWv[preSegNum][1] = preSegName
	indexWv[postSegNum][1] = postSegName
	indexWv[preSegNum][2] = "1"	//supposed to be a show/hide option. not sure I've ever used, anyway, default to show with 1
	indexWv[postSegNum][2] = "1"
		//rename the references to remaining segments appopriately
	Variable i,numSegs = dimsize(indexWv,0); String currSegRef, changeToRef
	for (i=numSegs-1;i>=nextSegNum;i-=1)		//start with last segment to avoid overwriting existing segments before renaming
		currSegRef = indexWv[i][0]
		changeToRef = tracedWaveName + "_c" + num2str(i)
		Duplicate/o $currSegRef, $changeToRef
		indexWv[i][0] = changeToRef
	endfor
	
	//now split the original segment into the two new ones
	Duplicate/O/R=[segPntNum,*][*] segWv,$postRef		//new wave starts with segPntNum
	Redimension/N=(segPntNum+1,-1) segWv 								//old wave ends with segPntNum +1 is because otherwise would go from pnt 0 to segPntNum-1. this way segments abut
	
	//now update row labels in all segments following the preSeg--the preSeg and those before it are unchanged because their number hasn't changed
	Variable j,numPointsInSeg;
	for (i=postSegNum;i<numSegs;i+=1)
		currSegRef = indexWv[i][0]
		WAVE segWv = $currSegRef
		numPointsInSeg = dimsize(segWv,0)
		for (j=0;j<numPointsInSeg;j+=1)
			setdimlabel 0,j,$(currSegRef+"_"+num2str(j)),segWv
		endfor	
	endfor
	Print "split segment at ccPnt",ccPntNum,"segPnt",segPntNum,"orig segnum",segNum,"named",origSegName,"into pre-seg num",preSegNum,"named",preSegName,"and post-seg num",postSegNum,"named",postSegName
	tracing_doUpdates(winN,nan,nan,nan)		//refreshes ccWv
end

function/S tracing_getLabelForCCPnt(winN,combinedWvPntNum)
	String winN
	Variable combinedWvPntNum
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef =  tracing_getCombinedSegref(tracedWaveName)
	
	if (numtype(combinedWvPntNum))
		combinedWvPntNum = tracing_getselpntdata(winN,nan)
	endif
	
		
	if (!WAveExists($combinedSegRef))
		return ""
	endif
	
	return getdimlabel($combinedSegRef,0,combinedWvPntNum)
end 

function tracing_segNumFromSegRef(segref)
	String segRef
	
	variable numSpace = itemsinlist(segRef,"_")
	string segAppendStr = stringfromlist(numSpace-2,segRef,"_")[1,inf]		//remove "c" at start"
	return str2num(segAppendStr)
end

function tracing_getSegPntFromSegRef(segref)	//good for gettign segment pnt from combined wave dim label
	String segRef
	
	variable numSpace = itemsinlist(segRef,"_")
	string pntNumStr = stringfromlist(numSpace-1,segRef,"_")
	return str2num(pntNumStr)
end


//for a row in the combined wave, returns the corresponding row in a segment wave
function tracing_getSegPntNumForCCPnt(winN,combinedWvPntNum)
	String winN
	Variable combinedWvPntNum

	String combinedWvRowLbl = tracing_getLabelForCCPnt(winN,combinedWvPntNum)
	return tracing_getSegPntFromSegRef(combinedWvRowLbl)
end

function tracing_getSegNumForCCPnt(winN,combinedWvPntNum)
	String winN
	Variable combinedWvPntNum

	String combinedWvRowLbl = tracing_getLabelForCCPnt(winN,combinedWvPntNum)
	return tracing_segNumFromSegRef(combinedWvRowLbl)
end

function/S tracing_getSegNameForCCPnt(winN,combinedWvPntNum)
	String winN;Variable combinedWvPntNum		//nan to get segName of selPnt

	String combinedWvRowLbl = tracing_getLabelForCCPnt(winN,combinedWvPntNum)
	Variable lastUS = strsearch(combinedWvRowLbl,"_",inf,1)
	//Variable secondLastUS = strsearch(combinedWvRowLbl,"_",lastUS-1,1)
	return combinedWvRowLbl[0,lastUS-1]
end

//returns wave in which ellipse points are stored for plotting
function/S tracing_getPlottedEllipseWvName(winN)
	String winN
	
	return winN + "_ell"
end
	
	
	
//checks if one or more points are traced onto winN, returns 1 if so
function tracing_doPlot(winN)
	String winN

	String tracedWaveName = img_getImageName(winN)

	String zWaveName = tracing_getZWaveRef(tracedWaveName)
	if (!WaveExists($zWaveName))
		return 0
	endif
	
	WAVE/T zWv= $zWaveName
	return strlen(zWv[0][0]) != 0		//true if there's a string in this position (empty when no points yet plotted)
end


function tracing_clearTracingOverlay(winN)
	String winN
	
	String tracedWaveName = img_getImageName(winN)
	String overlayWvSaveName = tracing_getOverlayWvRef(tracedWaveName)
	String colorWvSaveName = tracing_getOverlayColorsWvRef(tracedWaveName)
	
	Make/D/O/N=(1,3) $overlayWvSaveName
	Make/O/N=(1,3) $colorWvSaveName
	WAVE overlayWv = $overlayWvSaveName; Wave colorWv = $colorWvSaveName	
	overlayWv = NaN
	colorWv = NaN
	
end

function tracing_refreshTracingOverlay(winN,highlightedSeg,highlightedSegPnt)
	String winN
	Variable highlightedSeg		//pass a valid segment number to fill in all points from that segment
	Variable highlightedSegPnt	//pass a valid pntNumber (row number) in highlightedSeg to highlight that point	
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	Variable zDistTol = 0.5		//count pixels in plane that are within half a z pixel, exclusive
		
	String tracedWaveName = img_getImageName(winN)
	String zWaveName = tracing_getZWaveRef(tracedWaveName)
	String indexWaveName = tracing_getTracingIndexWaveRef(tracedWaveName)
	String overlayWvSaveName = tracing_getOverlayWvRef(tracedWaveName)
	String colorWvSaveName = tracing_getOverlayColorsWvRef(tracedWaveName)
	String markerWvSaveName = tracing_getOverlayMarkerWvRef(tracedWaveName)
	Variable zCenter = img_getDisplayedPlane(winN)
	
	if (numtype(highlightedSeg))
		highlightedSeg = tracing_getCurrSegNum(winN)
	endif
	
	if ( numtype(highlightedSegPnt) && (numtype(highlightedSeg) == 0) )
		highlightedSegPnt = tracing_getSelPntData(winN,highlightedSeg)
	endif
			
	if (!tracing_doPlot(winN))
		tracing_clearTracingOverlay(winN)
		return 0
	endif
	
	//color
	Variable planeDepth = 25			//how far out of plane one can "see"
	Variable positiveGun = 0			//positive red (gun 0)
	Variable negativeGun = 2			//negative blue
	Variable maxColorVal = 50000
	Variable minColorVal = 1000
	Variable colorWorkingRange = maxColorVal -  minColorVal
	
	//transparency
	Variable alphaGun = 3
	Variable alphaVal
	String opacSliderN = tracing_getOpacSliderName()
	String opacWinN = win_getFirstDerivedWinName(opacSliderN)

	//marker
	Variable nonHighlightedSegMarkerNum = 7		//8 is unfilled circle		//19 is filled circle
	Variable highlightedSegMarkerNum = 8		//0 is filled cicle		//54 is open hexagons		//7 is open diamond
	Variable nonHighlightedPntMarkerNum  = nonHighlightedSegMarkerNum	//not really worth differentiating random points in other segments?
	Variable highlightedPntMarkerNum  = 19		//17 is closed triangle	//55 is closed hexagons		//18 is closed diamond		//41 is open circle with center dot
	
	if ( (strlen(opacWinN) < 1) || (wintype(opacWinN) == 0))
		alphaVal = -1 + 2^16
	else
		ControlInfo/W=$opacWinN $opacSliderN
		alphaVal = V_Value
	endif
	
	WAVE/T zWv = $zWaveName
	WAVE/T indexWv = $indexWaveName
	
	if (strlen(zWv[0][0]) == 0)		//empty, so cleared
		tracing_clearTracingOverlay(winN)
	endif
	
	Variable i,j, overlayIndex=0, currPixel_z, numPoints, currPointRow, currPixelVal_x, currPixelVal_y, currTracingComponentNum
	String currPointsList, currTraceWvPntPair, currTraceWvRef
	Variable currZDist, normalizedZDepth		//latter relative to plane depth
	Variable firstDrawnZFound = 0
	
	Variable pntSegNum, isHighlightedSeg, isHighlightedSegPnt		//tracks whether each pnt is in the highlighted segment or is the highlighted pnt
	Variable markerNum	//markerNum to be applied to each pnt (Determined by comparing pntSegNum,currPointRow with isHighlightedSeg, isHighlightedSegPnt	)
	for (i=0;i<DimSize(zWv,0);i+=1)
		currPixel_z = str2num(zWv[i][0])
		numPoints = str2num(zWv[i][1])
		currPointsList = zWv[i][2]
		currZDist = zCenter - currPixel_z
		
		if (abs(currZDist) > planeDepth)		//skip z values out of plane depth
			continue
		endif	
		
		normalizedZDepth = abs(currZDist) / planeDepth
		if (firstDrawnZFound==0)		//first row, make new wave with correct number of points
			Make/O/N=(numPoints,3) $overlayWvSaveName/WAVE=overlayWv
			Make/U/O/N=(numPoints,4) $colorWvSaveName/WAVE=colorWv		//made type unsigned in later
			Make/U/O/N=(numPoints) $markerWvSaveName/WAVE=markerWv
			firstDrawnZFound = 1
		else
			Redimension/N=(DimSize(overlayWv,0) + numPoints,-1) overlayWv
			Redimension/N=(DimSize(colorWv,0) + numPoints,-1) colorWv
			Redimension/N=(DimSize(markerWv,0) + numPoints) markerWv
		endif
		
		for (j=0;j<numPoints;j+=1)
			currTraceWvPntPair = StringFromList(j, currPointsList)
			currTraceWvRef = StringFromList(0, currTraceWvPntPair,",")			
			currPointRow = str2num(StringFromList(1, currTraceWvPntPair,","))
			pntSegNum = str2num(stringfromlist(2,currTraceWvPntPair,","))
			currTracingComponentNum = str2num(StringFromList(2, currTraceWvPntPair, ","))		//get the component number for this point
			currPixelVal_x = getWaveV_val_2D(currTraceWvRef, currPointRow, 0)			//takes precise click loc rather than pixel val
			currPixelVal_y = getWaveV_val_2D(currTraceWvRef, currPointRow, 1)		
			
			if (str2num(indexWv[currTracingComponentNum][2]))		//is there a one in the 2nd column of the row of the component for this point?
				colorWv[overlayIndex][alphaGun] = alphaVal		//sets transparency to current value
			else
				colorWv[overlayIndex][alphaGun] = 0		//sets transparency to zero (implements hiding of segments
			endif
			
			overlayWv[overlayIndex][0] = currPixelVal_x
			overlayWv[overlayIndex][1] = currPixelVal_y
			overlayWv[overlayIndex][2] = currPixel_z
			
			if (abs(currZDist) < zDistTol)		//at exact plane of focus
				colorWv[overlayIndex][0] = 32792
				colorWv[overlayIndex][1] = 65535	
				colorWv[overlayIndex][2] = 1			
				//make white
			else
				colorWv[overlayIndex][0,2] = minColorVal + colorWorkingRange*(normalizedZDepth)	//moving towards brightest as farther away
				if (currZDist < 0)		//below plane
					colorWv[overlayIndex][positiveGun] = maxColorVal		//always brightest
				else						//above plane
					colorWv[overlayIndex][negativeGun] = maxColorVal
				endif
			endif
		
			//handle how to "highlight" pnt by marker type
			isHighlightedSeg = pntSegNum == highlightedSeg
			isHighlightedSegPnt = currPointRow == highlightedSegPnt
			if (isHighlightedSeg)
				if (isHighlightedSegPnt)
					markerNum = highlightedPntMarkerNum
				else
					markerNum = highlightedSegMarkerNum
				endif
			else
				if (isHighlightedSegPnt)
					markerNum = nonHighlightedPntMarkerNum
				else
					markerNum = nonHighlightedSegMarkerNum
				endif
			endif
			markerWv[overlayIndex] = markerNum
			
			
			overlayIndex += 1
		endfor
	endfor
	
		//handle if there is nothing to plot at present (e.g. moved too far from plane of tracing)
	if (overlayIndex == 0)
		tracing_clearTracingOverlay(winN)
	else
	
		//handle plotting if there is something to plot
		Variable waveOnGraph = ItemsInList(ListMatch(text_getWvListFromTraceList(winN,traceNameList(winN,";",1)), overlayWvSaveName))
		if (!waveOnGraph && (DimSize(overlayWv,1) > 1) )
			AppendtoGraph/W=$winN/T/L overlayWv[][1]/TN=$overlayWvSaveName vs overlayWv[][0]		//y_pixels vs x_pixels
			ModifyGraph/W=$winN zColor($overlayWvSaveName)={$colorWvSaveName,*,*,directRGB,0}, mode=3,msize=2
			ModifyGraph/W=$winN zmrkNum($overlayWvSaveName)={$markerWvSaveName}
			 
		//	String pzWin=tracedWaveName+"pzW" //p vs z with q in layers, equiv y vs z with x in layers -- swap for [p][r][q] 
		//	String zqWin=tracedWaveName+"zqW" //z vs q with 	p in layers, equiv z vs x with y in layers -- swap for [r][q][p]
			
//			if (wintype(pzWin) > 0)			//pz keeps y so plot y vs z
//				AppendtoGraph/W=$pzWin/T/L overlayWv[][1] vs overlayWv[][2]
//				Modifygraph/W=$pzWin zColor={$colorWvSaveName,*,*,directRGB,0},mode=3,msize=2,zmrkNum($overlayWvSaveName)={$markerWvSaveName}
//			endif
//			if (wintype(zqWin) > 0)			//zq keeps x so plot z vs x
//				AppendtoGraph/W=$zqWin/T/L overlayWv[][2] vs overlayWv[][0]
//				Modifygraph/W=$zqWin zColor={$colorWvSaveName,*,*,directRGB,0},mode=3,msize=2,zmrkNum($overlayWvSaveName)={$markerWvSaveName}
//			endif
		endif
	endif
	
			String pzWin=tracedWaveName+"pzW" 
			String zqWin=tracedWaveName+"zqW"
				//AppendtoGraph/W=$pzWin/T/L overlayWv[][1] vs overlayWv[][2]		//plot is y along top and z along x/left
				//Modifygraph/W=$pzWin zColor={$colorWvSaveName,*,*,directRGB,0},mode=3,msize=2,zmrkNum($overlayWvSaveName)={$markerWvSaveName}
				//AppendtoGraph/W=$zqWin/T/L overlayWv[][2] vs overlayWv[][0]		//plot is z along top and x along x/left
				//Modifygraph/W=$zqWin zColor={$colorWvSaveName,*,*,directRGB,0},mode=3,msize=2,zmrkNum($overlayWvSaveName)={$markerWvSaveName}
end//tracing_refreshTracingOverlay()

	
function tracing_addPointFromClickLoc(s)		//adds a point
	STRUCT WMWinHookStruct &s

	Variable xPixelVal, yPixelVal
	xPixelVal = disp_getMouseLoc(s, "top")	
	yPixelVal = disp_getMouseLoc(s, "left")
	
	String imgName = img_getImageName(s.winName)
	Variable zPixel = img_getDisplayedPlane(s.winName)
	
	Variable redoRows =  (s.eventMod & 2^1) != 0		//shift click, overwrites last added point instead of adding a new one
	Variable overwritePnt = redoRows && ( (s.eventMod & 2^3) != 0	)	//CTRL + SHIFT click -- overwrite point selection
//	print "redoRows",redoRows,"overwritePnt",overwritePnt
	Variable numPointsToDelete,deleteWithoutAddition=0
	if (redoRows && !overwritePnt)		//ignore redo rows if overwriting a point
		numPointsToDelete = 1		//sets default num pnts to delete at 1
		prompt numPointsToDelete, "Enter num points to remove"
		prompt deleteWithoutAddition,"skip addition?"
		doprompt "Remove points", numPointsToDelete,deleteWithoutAddition
	else		
		numPointsToDelete = 0
	endif
	
	if (overwritePnt)
		Variable selPnt = tracing_getSelPntData(s.winname,nan)
		tracing_addPoint(s.winName,xPixelVal,yPixelVal,zPixel,numPointsToDelete,overwriteCCPnt=selPnt,noAddition=deleteWithoutAddition)
	else
		tracing_addPoint(s.winName,xPixelVal,yPixelVal,zPixel,numPointsToDelete,noAddition=deleteWithoutAddition)
	endif
end

function/S tracing_getOpacSliderName()

	return "tracing_opacity"
end

//MUST have traced image on top
function tracing_showOpacitySlider()
	String opacWinN = tracing_getOpacSliderName()
	
	Variable maxVal = (2^16)-1		//assumes 16 bit "RGBa" color. default is to have full opacity (a)
	
	String tracingWinN = winname(0,1)
	
	if (!Wintype(opacWinN))
		Display/K=1/N=$opacWinN
		Slider $opacWinN limits={0,maxVal,0}, size={50,100}, pos={0,0}, proc=tracing_opacSliderAction, userdata=tracingWinN, value=maxVal
	endif
end

function tracing_opacSliderAction(s)
	STRUCT WMSliderAction &s

//	String camName = StringFromList(0, s.ctrlName, "_")
//	ModifyCamera/W=$camName setSharpening=s.curval

	tracing_refreshTracingOverlay(s.userdata,nan,nan)
end

function tracing_addPoint(winN,xPixelVal,yPixelVal,zPixel,numPointsToDelete,[overwriteCCPnt,noAddition])
	String winN;
	Variable xPixelVal, yPixelVal	//stored as float point closest to click--maps onto axis space not pixel space, round to integer to get pixel
	Variable zPixel				//maps onto layer space, so consider each slice an integer pixel
	Variable numPointsToDelete			//if zero, a new point is added (standard use). If 1 or greater, input starts from that many points preceding, up to the beginning of the Segment
	Variable noAddition		//allows point deletion without addition of subsequent new points. pass true, otherwise ignored

	Variable overwriteCCPnt		//optionally pass to overwrite the point at the index passed -- numPointsToDelete is ignored!
	Variable autoRadius_pixels = 30

	Variable highlightCurrSeg = 1	//set whether to highlight the current seg and pnt (see tracing_refreshTracingOverlay)
	Variable highlightCurrPnt = 1

	Variable numStoredTraceParams = 7
	SVAR/Z tracing_currTracingWaveName
	
	if (!Svar_exists(tracing_currTracingWaveName))
		Print "tracing_addPoint(): Failed to find required global string tracing_currTracingWaveName. Likely need to use tracing_addSeg(seg#,\"segName\") to instantiate it"
		return 0
	endif
	
	String imgName = img_getImageName(winN)
	
	Variable xNearestPixel = round(xPixelVal)
	Variable yNearestPixel = round(yPixelVal)
	
	Variable currRow 
	
	String combinedSegRef,usedSegRef="",savedSegRef=""
	if (!ParamIsDefault(overwriteCCPnt))
		combinedSegRef = tracing_getCombinedSegref(imgName)
		WAVE/Z/D combinedSegWv = $combinedSegRef
		if (!WaveExists(combinedSegWv))
			Print "tracing_addPoint() request to overwrite ccPnt",overwriteCCPnt,"failed. combinedSegRef",combinedSegRef,"does not exist.aborting"
			return 0
		endif
		Variable pnts = dimsize(combinedSegWv,0)
		if (numtype(overwriteCCPnt) || (overwriteCCPnt<0) ||  (overwriteCCPnt>(pnts-1))  )
			Print "tracing_addPoint() request to overwrite ccPnt",overwriteCCPnt,"failed. overwriteCCPnt is out of range or not a real number. aborting"
			return 0
		endif
		
		savedSegRef=tracing_currTracingWaveName
		usedSegRef=tracing_getSegNameForCCPnt(winN,overwriteCCPnt)
		tracing_currTracingWaveName = usedSegRef
		Variable selPnt_segIndex = tracing_getSegPntNumForCCPnt(winN,overwriteCCPnt)
		currRow = selPnt_segIndex
	endif
	
	
	WAVE/Z/D currTracingWv = $tracing_getSegNameForCCPnt(winN,nan)
	
	if (!WaveExists(currTracingWv))
		Make/O/N=(1,numStoredTraceParams)/D $tracing_currTracingWaveName		//5 stores radius of current point in absolute value, 6 does it in pixels . 5 is obsolute
		WAVE/Z/D currTracingWv = $tracing_currTracingWaveName
		tracing_setSegColumnsLbls(tracing_currTracingWaveName)
		currRow = 0
	else
		if (numtype(currTracingWv[0][0]) != 0)		//filled with NaNs if no points yet
			currRow = 0
		elseif (!ParamIsDefault(overwriteCCPnt) && overwriteCCpnt && (numPointsToDelete < 1))
			//do nothing! Point will be filled in with new values		
		else		//normal case, 
			currRow = tracing_getSelPntData(winN,-1)+1 //DimSize(currTracingWv,0) <-- had been setting for years but means no points always add at end of segment, which is bad for adding out of order
			if (numPointsToDelete)		//shift key down, redo last point)
				deletepoints/M=(0) currRow - numPointsToDelete, numPointsToDelete, currTracingWv				
				currRow -= numPointsToDelete
				if (currRow < 0)
					currRow = 0		//truncate at zero
				endif
			endif
			insertpoints/m=(0)/v=(nan) currRow,1,currTracingWv
		endif
	endif
 
	Variable rows=dimsize(currTracingWv,0),i
	for (i=currRow;i<rows;i+=1)
		SetDimLabel 0,i,$(tracing_currTracingWaveName+"_"+num2str(i)),currTracingWv
	endfor
	
	if (ParamIsDefault(noAddition) || !noAddition)
		currTracingWv[currRow][0] = xPixelVal
		currTracingWv[currRow][1] = yPixelVal
		currTracingWv[currRow][2] = xNearestPixel
		currTracingWv[currRow][3] = yNearestPixel
		currTracingWv[currRow][4] = zPixel
	endif
	
	if (ParamIsDefault(overwriteCCPnt))
		//save the cross section information for the previous wave
		if  (currRow > 0)
			currTracingWv[currRow][5,6] = currTracingWv[currRow-1][q]
			Variable currCrossSectInPix = currTracingWv[currRow][6]
			if (numtype(currCrossSectInPix) == 0)		//not NaN etc.
				tracing_setCurrCrossSectSize(winN,currCrossSectInPix,0)
			endif
		else
			Variable segNum = tracing_getCurrSegNum(winN)
			if (segNum == 0)		//very first point, just make something up for radius
				currTracingWv[0][6] = autoRadius_pixels
				currTracingWv[0][5] = nan
			else				//first point in segment, get the radius of the last point in the preceding segment and copy that over	
				String tracingIndexWvRef = tracing_getTracingIndexWaveRef(imgName)
				WAVE/T tracingIndexWv = $tracingIndexWvRef		
				String lastTracingWvRef = tracingIndexWv[segNum-1][0]
				WAVE lastTracingWv = $lastTracingWvRef
				Variable lastWvLastPnt = dimsize(lastTracingWv,0) - 1
				if ( (lastWvLastPnt < 0) || numtype(lastWvLastPnt) )		//no pnts in that wave .. set to automatic value
					currTracingWv[0][6] = autoRadius_pixels
					currTracingWv[0][5] = nan								
				else
					currTracingWv[currRow][5,6] = lastTracingWv[lastWvLastPnt][q]
				endif			
			endif	
		endif
	endif
	
//	Print "currTracingWvRef",nameofwave(currTracingWv),"usedSegRef",usedSegRef,"savedSegRef",savedSegRef,"currRow",currRow,"xVal=" + num2str(xPixelVal ) + ". xNearestPixel=" + num2str(xNearestPixel ) + ". yVal=" + num2str(yPixelVal ) + ". yNearestPixel=" + num2str(yNearestPixel )
	
	tracing_updateZWave(imgName)
	tracing_showSegTable_ref(imgName);
	
	Variable displaySegment, displayPnt; STRING indexRef,searchStr	
	
	if (highlightCurrPnt)
		searchStr = tracing_currTracingWaveName + "_" + num2str(currRow)
		combinedSegRef = tracing_getCombinedSegref(imgName)
		WAVE/T segWv = $combinedSegRef
		if (WaveExists(segWv))
			displayPnt = FindDimLabel(segWv, 0, searchStr )
			if (displayPnt < 0)
				displayPnt = DimSize(segWv,0)-1
			endif
		else
			displayPnt = NaN
		endif
	else
		displayPnt = NaN	
	endif
	
	if (ParamIsDefault(overwriteCCPnt))
		tracing_follow(winN,displayPnt,nan,0)		//might be good to substitute this for tracing_doUpdates in future. that function is called by follow anyway
		//tracing_updateCrossSectXYWv(winN, tracing_currTracingWaveName, currRow)		//obsolete
	else
		tracing_follow(winN,overwriteCCPnt,nan,0)
		tracing_currTracingWaveName = savedSegRef
	endif
end


function tracing_doUpdates(winN,currSegRow_forCrossSect,highlightedSeg,highlightedSegPnt)
	String winN
	Variable currSegRow_forCrossSect
	Variable highlightedSeg,highlightedSegPnt	//see tracing_refreshTracingOverlay
	
	Variable tracingWvFollowsHighlightedSeg = 1		//170613 new option: change tracing wave to that of selected point
																//previously tracing wave was always that assigned during tracing
																
	if (!strlen(winN))
		winN = winname(0,1)	//topgraph
	endif
	
	String imgName = img_getImageName(winN)
	
	if (tracingWvFollowsHighlightedSeg)
		String tracingIndexWvRef = tracing_getTracingIndexWaveRef(imgName)
		WAVE/T/Z tracingIndexWv = $tracingIndexWvRef
		if (!WaveExists(tracingIndexWv))
			return 0
		endif
		//is the selected segment a valid, traced segment?
		if ( (highlightedSeg >= 0) && (highlightedSeg < dimsize($tracingIndexWvRef,0)) )
			String/G tracing_currTracingWaveName = tracingIndexWv[highlightedSeg][0]
			//Print "tracing_currTracingWaveName set to",tracing_currTracingWaveName,"segName",tracingIndexWv[highlightedSeg][1]
		endif
	endif
	
	SVAR/Z tracing_currTracingWaveName
	if (!Svar_exists(tracing_currTracingWaveName))
		Print "tracing_doUpdates(): failed to find current tracing wave!"
		return 0
	endif
	
	tracing_updateZWave(imgName)
	//tracing_updateCrossSectXYWv(winN, tracing_currTracingWaveName, currSegRow_forCrossSect,setRadiusToStoredVal=1)		//obsolete, replaced by tracing_setCurrCrossSectSize
	tracing_setCurrCrossSectSize(winN,0,1)			//pass as increment of zero to set to current points value
	tracing_showSegTable_ref(imgName)//,1)	
	tracing_refreshTracingOverlay(winN,highlightedSeg,highlightedSegPnt)	
	
end


//calls tracing_repeatPoint() if enter click event is passed
function tracing_enterRepeatsPoint(s)
	STRUCT WMWinHookStruct &s
	
	if (s.keycode != 13)
		return 0
	endif
	
	tracing_repeatPoint(s.winName)

end

//currently called by pressing enter. See tracing_enterRepeatsPoint(s)
function tracing_repeatPoint(winN)	
	String winN

//OLD WAY	
//	WAVE/D crossSectSizeWv = $tracing_getCrossSectSizeWvRef()
//	WAVE/D crossSectXYPosWv = $tracing_getCrossSectXYWvRef()
//	
//	Variable lastPixelVal_x = crossSectXYPosWv[0][0]
//	Variable lastPixelVal_y = crossSectXYPosWv[0][1]
//	Variable lastPixel_z = img_getDisplayedPlane(winN)

	int selPnt_overallIndex = tracing_getSelPntData(winN,nan)
	int selPnt_segIndex = tracing_getSegPntNumForCCPnt(winN,selPnt_overallIndex)
	int selPntSegNum = tracing_getSegNumForCCPnt(winN,selPnt_overallIndex)
	
	String tracedWaveName = img_getImageName(winN)	
	String indexWvRef = tracing_getTracingIndexWaveRef(tracedWaveName)
	WAVE/T/z indexWv = $indexWvRef
	String segWvRef = indexWv[selPntSegNum][0]
	WAVE segWv = $segWvRef
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D combinedSegWv = $combinedSegRef
	
//	WAVE/D currTracingWv = $tracing_getSegNameForCCPnt(winN,nan)
	Variable lastPnt = selPnt_overallIndex - 1
	Variable lastPixelVal_x = combinedSegWv[lastPnt][%xPixLoc]
	Variable lastPixelVal_y = combinedSegWv[lastPnt][%yPixLoc]
	Variable lastPixel_z = combinedSegWv[lastPnt][%zPixLoc]
	
	tracing_addPoint(winN, lastPixelVal_x, lastPixelVal_y, lastPixel_z, 0)	
end		


	Variable selPnt_overallIndex = tracing_getSelPntData(winN,nan)
	Variable selPnt_segIndex = tracing_getSegPntNumForCCPnt(winN,selPnt_overallIndex)
	Variable selPntSegNum = tracing_getSegNumForCCPnt(winN,selPnt_overallIndex)
		
	String tracedWaveName = img_getImageName(winN)	
	String indexWvRef = tracing_getTracingIndexWaveRef(tracedWaveName)
	WAVE/T/z indexWv = $indexWvRef
	String segWvRef = indexWv[selPntSegNum][0]
	WAVE segWv = $segWvRef
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D combinedSegWv = $combinedSegRef


//CROSS SECTION ESTIMATES: current cross section estimate stored in tracing_currCrossSectSizes, xy pos for this in tracing_currCrossSectXYPos
//this info stored in  tracing_getCrossSectSizeWvRef()	 and tracing_getCrossSectXYWvRef()

//170613 modified to move for ctrl + scroll wheel or ctrl + up down arrow key
function tracing_updatesCrossSect(s)
	STRUCT WMWinHookStruct &s
	
	Variable scrollEvent = (s.eventCode == 22) && ((s.eventMod & 2^3) != 0)		//22 is wheel event
	Variable arrowKeysEvent =  (s.keycode == 30) || (s.keycode == 31 )
	
	if (!scrollEvent && !arrowKeysEvent)
		return 0
	endif
			
	Variable fineOrCoarse = (s.eventMod & 2^1) != 0		//returns true WITH SHIFT key, so USE SHIFT (along with cntrl) key to get COARSE
	
	Variable scrollVal
	
	if (scrollEvent)
		scrollVal = s.wheelDy  == 0 ? 0 : (s.wheelDy > 0 ? 1 : -1)		//the case of equal to zero probably never happens
																					//but different types of mice (particularly laptop pads vs actual mice) have different scales, so the +/- == 1/-1 equalizes
	elseif (arrowKeysEvent)
		scrollVal = s.keycode == 30 ? 1 : -1		//up arrow is 30, down is 31
	else
		return 0
	endif
	
	if (tracing_doPlot(s.winName))
		tracing_incrCrossSectSize(s.winName,scrollVal, fineOrCoarse)
	endif
	
	return arrowKeysEvent		//return 1 to tell passing function to also return 1 and deal with the keyboard event, rather than letting Igor
end

function tracing_incrCrossSectSize(winN,V_arbitIncrement,fineOrCoarse)
	STring winN
	Variable V_arbitIncrement	//arbitrary unit (for scroll its -1 or +1), scaling set here
	Variable fineOrCoarse
		
	Variable sizeChangePerArbitraryUnit
	if (fineOrCoarse)
		sizeChangePerArbitraryUnit = 1		//coarse. pixels.
	else
		sizeChangePerArbitraryUnit = 0.1	//fine. half a pixel (diameter of one pixel)
	endif
	
	Variable scaledIncrement = V_arbitIncrement * sizeChangePerArbitraryUnit
		
	tracing_setCurrCrossSectSize(winN,scaledIncrement,1)
end

//no longer needed because now draws an ovall and always saved radius in wave
//function tracing_saveCrossSectLastInWv()	
//	SVAR/Z tracing_currTracingWaveName
//	
//	if (!svar_exists(tracing_currTracingWaveName))
//		Print "tracing_saveCrossSectLastInWv(): Failed to find required global string tracing_currTracingWaveName. Likely need to use tracing_addSeg(seg#,\"segName\") to instantiate it"
//		return 0
//	endif
//	
//	Variable currCrossSectSize = tracing_getCurrCrossSectsize()
//		
//	WAVE/Z tracingWv = $tracing_currTracingWaveName
//	if (!WaveExists(tracingWv))
//		Print "tracing_saveCrossSectLastInWv(): Failed to find required wave in ref tracing_currTracingWaveName. Likely need to use tracing_addSeg(seg#,\"segName\") to instantiate it"
//		return 0
//	endif
//	
//	variable lastPntRow = DimSize(tracingWv,0)-1
//	if (lastPntRow < 0)
//		lastPntRow=0		//truncate at zero
//		redimension/n=(1,-1) tracingWv		//can actually get zero rows and cause an error!
//	endif
//	
//	tracingWv[lastPntRow][5] = tracing_getCurrCrossSectsize()
//	tracingWv[lastPntRow][6] = tracing_getCurrCrossSectsize(winN=winname(0,1))
//end

//added 170613
//FOR USE WITH TRACKING BACK TO POINTS AFTER TRACING, when one wants to update cross section
//not originally intended for updating cross section while in the process in tracing, not sure
//how that would go.

//now obsolete because cross-section is stored directly and an oval trace is updated
//function tracing_storeZValueForCurrPnt(winN,[useValFromDelta,setToPixelVal,setDisplay])
//	String winN
//	Variable useValFromDelta	//pass to store the radius for this point not as what is currently displayed but instead a point number offset from this one by the passed value
//									//passing 0 should behave as if the optional parameter wasnt passed
//	Variable setToPixelVal	//set to command a new pixel value width; this has priority
//	Variable setDisplay		//if passed and true, tracing_setCurrCrossSectSize is called to update that to the value for this point
//	
//	if (!strlen(winN))
//		winN = winname(0,1)
//	endif
//
//	Variable selPnt_overallIndex = tracing_getSelPntData(winN,nan)
//	Variable selPnt_segIndex = tracing_getSegPntNumForCCPnt(winN,selPnt_overallIndex)
//	Variable selPntSegNum = tracing_getSegNumForCCPnt(winN,selPnt_overallIndex)
//		
//	String tracedWaveName = img_getImageName(winN)	
//	String indexWvRef = tracing_getTracingIndexWaveRef(tracedWaveName)
//	WAVE/T/z indexWv = $indexWvRef
//	
//	if (!WaveExists(indexWv))
//		return 0
//	endif
//	
//	if (selPntSegNum >= dimsize(indexWv,0))
//		Print "tracing_storeZValueForCurrPnt(): z value not stored because sel pnt is now not in an existing segment, likely segments were combined or deleted"
//		return 0
//	endif
//	if (numtype(selPntSegNum))
//		selPntSegNum=0
//	endif
//	String segWvRef = indexWv[selPntSegNum][0]
//	WAVE segWv = $segWvRef
//		
//	Variable crossSectSize_pnts,crossSectSize_pix
//	
//	if (!ParamIsDefault(setToPixelVal))
//		crossSectSize_pix = setToPixelVal
//		crossSectSize_pnts = img_pixelsToAbsCircleMrkSize(winN, crossSectSize_pix, 0)
//	elseif (ParamIsdefault(useValFromDelta))
//		crossSectSize_pnts = tracing_getCurrCrossSectsize()
//		crossSectSize_pix = tracing_getCurrCrossSectsize(winN=winN)	
//	else
//		String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
//		WAVE combinedSegWv = $combinedSegRef
//		Variable indexToGetCrossSectFrom = selPnt_overallIndex + useValFromDelta
//		indexToGetCrossSectFrom = tracing_truncPntValueIfNeeded(indexToGetCrossSectFrom,winN)
//		crossSectSize_pix = combinedSegWv[indexToGetCrossSectFrom][6]	
//		crossSectSize_pnts = img_pixelsToAbsCircleMrkSize(winN, crossSectSize_pix, 0)
//		
//		//seems redundent (in truth the former might be) but also need to set the displayed cross section radius to avoid the former change being overwritten
//		//added bonus of immediately updating the display to be consistent with the stored value
//		String crossSectSizeWvRef = tracing_getCrossSectSizeWvRef()
//		WAVE crossSectSizeWv = $crossSectSizeWvRef
//		crossSectSizeWv[0] = crossSectSize_pnts	
//	endif
//	if (numtype(selPnt_segIndex))
//		selPnt_segIndex=0
//	endif	
//	segWv[selPnt_segIndex][5] = nan	//no longer ud
//	segWv[selPnt_segIndex][6] = crossSectSize_pix
//	
//	if (!ParamIsDefault(setDisplay) && setDisplay)
//		tracing_setCurrCrossSectSize(crossSectSize_pnts)
//	endif
//	
//	//tracing_doUpdates(winN,nan,nan,nan)
//end

//RETURNS NaN IF CROSS SECT ESTIMATOR IS HIDDEN

//obsolete since now size is stored directly in wave
//function tracing_getCurrCrossSectsize([winN])
//	String winN		//returns in pixels if win name is passed
//	
//	String crossSectSizeWvRef = tracing_getCrossSectSizeWvRef()
//	WAVE crossSectSizeWv = $crossSectSizeWvRef
//		
//	if (ParamIsDefault(winN))
//		return tracing_isSectWaveHidden() ? NaN : crossSectSizeWv[0]			//returns abs value if section wave is visible, NaN if absnet
//	endif
//	
//	return tracing_isSectWaveHidden() ? NaN : img_absCircleMrkToPixels(winN, crossSectSizeWv[0], 0)		//returns scaled section estimate if section wave is visible
//end

//pass radiusPix = 0, asIncrement=1 to refresh display to that of current point
//pass radiusPix = nan to copy radius from another point. asIncrement = -1 to copy preceding point in ccWv,+1 to copy next point in ccWv
function tracing_setCurrCrossSectSize(winN,radiusPix,asIncrement)
	String winN
	Variable radiusPix		//in pixel coordinates
	Variable asIncrement	//will add radiusPix to current radius (get subtraction by passing negative values)

	//get point info so we can change drawing of cross section
	Variable selPnt_overallIndex = tracing_getSelPntData(winN,nan)
	Variable selPnt_segIndex = tracing_getSegPntNumForCCPnt(winN,selPnt_overallIndex)
	Variable selPntSegNum = tracing_getSegNumForCCPnt(winN,selPnt_overallIndex)
		
	String tracedWaveName = img_getImageName(winN)	
	String indexWvRef = tracing_getTracingIndexWaveRef(tracedWaveName)
	WAVE/T/z indexWv = $indexWvRef
	String segWvRef = indexWv[selPntSegNum][0]
	WAVE segWv = $segWvRef
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D combinedSegWv = $combinedSegRef
	
	Variable xPixLoc=segWv[selPnt_segIndex][%xPixLoc]
	Variable yPixLoc=segWv[selPnt_segIndex][%yPixLoc]
	Variable origRadiusPix=segWv[selPnt_segIndex][%radiusPix]
	
	Variable newRadiusPix
	if (numtype(radiusPix))		//copy from ccWv
		Variable targetPnt = selPnt_overallIndex + asIncrement
		if (targetPnt < 0)
			print "tracing_setCurrCrossSectSize() tried to copy radius from preceding point but this is the first point! (usually occurs due to page down press). aborting"
			return 0
		endif
		Variable maxCcPnt = dimsize(combinedSegWv,0)-1
		
		if (targetPnt >maxCcPnt)
			print "tracing_setCurrCrossSectSize() tried to copy radius from next point but this is the last point! (usually occurs due to page up press). aborting"
			return 0			
		endif
	
		newRadiusPix = combinedSegWv[targetPnt][%radiusPix]
	else		//use input
		if (asIncrement)
			newRadiusPix = origRadiusPix + radiusPix
		else
			newRadiusPix = radiusPix
		endif	
	endif
	
	//store radius in segment wave and overall ccPnt wave
	segWv[selPnt_segIndex][%radiusPix]=newRadiusPix	
	combinedSegWv[selPnt_overallIndex][%radiusPix]=newRadiusPix
	
	//draw cross section
	tracing_setDrawnCrossSect(winN,xPixLoc,yPixLoc,newRadiusPix)
	
	//just for clarity NaN these since they are obsolete
	segWv[selPnt_segIndex][%radiusPnts]=nan	
	combinedSegWv[selPnt_overallIndex][%radiusPnts]=nan
	
	//OLD VERSION: use a zmarker size wave, but seemingly stopped follow radius
	//String crossSectSizeWvRef = tracing_getCrossSectSizeWvRef()
	//WAVE crossSectSizeWv = $crossSectSizeWvRef
	//crossSectSizeWv[0] = absSize
end

function tracing_setDrawnCrossSect(winN,xPixLoc,yPixLoc,radiusPix)
	Variable xPixLoc,yPixLoc,radiusPix
	String winN
	
	Variable left = xPixLoc - radiusPix
	Variable right = xPixLoc + radiusPix
	Variable top = yPixLoc + radiusPix
	Variable bottom = yPixLoc - radiusPix
	
	//check if an oval is already drawn and delete it
	setdrawlayer userfront
	drawaction getgroup=crossSection
	if (V_flag)
		drawaction getgroup=crossSection,delete,beginInsert
	endif
	
	//refresh an oval drawing
	setdrawenv gstart,gname=crossSection
	setdrawenv xcoord=top,ycoord=left,fillpat=0,linefgc= (65535,0,0)		//transparent fill and red outline,x and y coordinates
	DrawOval/W=$winN left, top, right, bottom
	setdrawenv gstop	
end

function tracing_getCurrCrossSectInPix(winN)
	String winN
	
	//get point info so we can change drawing of cross section
	Variable selPnt_overallIndex = tracing_getSelPntData(winN,nan)
	Variable selPnt_segIndex = tracing_getSegPntNumForCCPnt(winN,selPnt_overallIndex)
	Variable selPntSegNum = tracing_getSegNumForCCPnt(winN,selPnt_overallIndex)
		
	String tracedWaveName = img_getImageName(winN)	
	String indexWvRef = tracing_getTracingIndexWaveRef(tracedWaveName)
	WAVE/T/z indexWv = $indexWvRef
	String segWvRef = indexWv[selPntSegNum][0]
	WAVE segWv = $segWvRef
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D combinedSegWv = $combinedSegRef
	
	return segWv[selPnt_segIndex][%radiusPix]
	
	
end


//this is stored in userdata (when tracing from image plotted with img_newImage)
function/S tracing_getTracedWvNameFromWin()
	
	String topWinN = winname(0,1)
	
	return tracing_getTracedWvNmFromWinN(topWinN)

end

function/S tracing_getTracedWvNmFromWinN(winN)
	String winN
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	getWindow $winN userdata
	
	return S_value
end

function/s tracing_getTracedWvNFromIndRef(tracingIndexRef)
	STring tracingIndexRef
	
	return stringfromlist(0,tracingindexref,"_ind")
end

//parses wave name of form blah_c# and returns blah
function/S tracing_getTracedWvNFromN(tracingWaveRef)
	String tracingWaveRef
	
	return stringfromlist(0,tracingwaveref,"_c")
	
	//old (not used)
	String tracedWaveName		//wave being traced, looked up from first part of tracingWaveRef
	String tempStr = ReplaceString("_c", tracingWaveRef,  " ")
	sscanf tempStr, "%s", tracedWaveName	
	return tracedWaveName
end

function tracing_updateZWave(tracedWaveName)
	String tracedWaveName
	
	WAVE/T/Z tracingIndexWave = $tracing_getTracingIndexWaveRef(tracedWaveName)
	
	if (!WaveExists(tracingIndexWave))
		return 0
	endif
	
	String zPixelsWvRef = tracing_getZWaveRef(tracedWaveName)
		
	Make/O/T/N=(1,3) $zPixelsWvRef
	WAVE/T zPixelsWv = $zPixelsWvRef
	zPixelsWv = ""
	
	Variable i,j, foundRow, uniqueSlicesFound = 0, currZPixel
	String currWaveName
	for (i=0;i<DimSize(tracingIndexWave,0);i+=1)	//for each segment
		currWaveName = tracingIndexWave[i][0]
		if (!WaveExists($currWaveName))
			continue		
		endif
		Duplicate/O $currWaveName, currTracingWv
//		Print "currWaveName = " + currWaveName
		
		for (j=0;j<DimSize(currTracingWv,0);j+=1)	//for each point (in each segment)
			currZPixel = currTracingWv[j][4]
		//	Print "currZPixel = " + num2str(currZPixel)
			
			if (numtype(currZPixel) != 0)		//indicates no point here yet
				continue
			endif
			findvalue/text=num2str(currZPixel) zPixelsWv //does this pixel val already have a row?
		//	Print "foundRow = " + num2str(foundRow)
			if (V_Value < 0)		//true if not found, no row for this pixel, so make one
				Redimension/N=(uniqueSlicesFound+1,-1) zPixelsWv		//avoids having to treat the first row as special
				foundRow = uniqueSlicesFound
				zPixelsWv[foundRow][0] = num2str(currZPixel)			//stores curr z pixel
				zPixelsWv[foundRow][1] = "0"		//will be made one in a moment (stores point num)
				zPixelsWv[foundRow][2] = ""		//need to instantiate to increment later
				uniqueSlicesFound += 1
			endif
			zPixelsWv[foundRow][1] = text_increment(zPixelsWv[foundRow][1],1)
			zPixelsWv[foundRow][2] += currWaveName + "," + num2str(j) + "," + num2str(i)	+ "," + ";"		//component name, point number, component number
		endfor
	endfor
end//tracing_updateZWave()

//presently assumes x axis = "top" and y axis = "left"
function img_absCircleMrkToPixels(winN, absVal, forYNotForX)
	String winN
	Double absVal
	Variable forYNotForX	//0 for x, 1 for y
	
	String vertAxName = "left"
	String horizAxName = "top"
		
	if (strlen(winN) == 0)
		winN = winname(0,1)
	endif
	
	
	getWindow $winN, psizeDC		//I used to use psizeDC but the output of that no longer makes any sense to me
	
	if (forYNotForX)		//if true, return for y
		Variable absRange_y = V_bottom - V_top
		GetAxis/Q/W=$winN $vertAxName
		Variable pixelRange_y = abs(V_max - V_min)
		Variable pixelsPerAbsUnit_y = pixelRange_y / absRange_y
		
		return absVal*pixelsPerAbsUnit_y
	else
		Variable absRange_x = V_right - V_left
		GetAxis/Q/W=$winN $horizAxName
		Variable pixelRange_x = abs(V_max - V_min)
		Variable pixelsPerAbsUnit_x = pixelRange_x / absRange_x
		return absVal*pixelsPerAbsUnit_x
	endif		
end

function img_pixelsToAbsCircleMrkSize(winN, pixelVal, forYNotForX)
	String winN
	Double pixelVal
	Variable forYNotForX

	Variable currentMrkSizeToPixFactor = img_absCircleMrkToPixels(winN, 1, forYNotForX)		//current number of pixels for a marker size of one (units: pix/markerSize)
	Variable absVal = pixelVal / currentMrkSizeToPixFactor //convert to current marker size for last stored pixels. units: pix /(pix/markerSize) = markerSize

	return absVal
end


//must have window selected
function tracing_addSeg(newOrSegmentNumToOverwrite,overwriteOrInsert,SegmentNameStr)
	Variable newOrSegmentNumToOverwrite		//-1 for new, or num of Segment to overwrite (numbered 0 to N-1 for N Segments) or insert BEFORE
	Variable overwriteOrInsert				//0 for overwrite, 1 for insert BEFORE the segment at number passed in newOrSegmentNumToOverwrite
	String SegmentNameStr
	
	Variable promptForRepeatPntOnFirstPnt = 1		//With the exception of the first segment, new segments should repeat the last point from the last segment
	
	Variable rowRequested = newOrSegmentNumToOverwrite
	
	String winN = winname(0,1)
	
	String tracedWaveName = img_getImageName(winN)		//assumes working with top graph
	Print "tracedWaveName",tracedWaveName
	
	//used for displaying tracing results
	SVAR/Z traceResultsTableN, allTraceResultsTableN
	if (!Svar_exists(traceResultsTableN))
		String/G traceResultsTableN = "currTracingMeasurements"
	endif
	if (!Svar_exists(allTraceResultsTableN))
		String/G allTraceResultsTableN = "currSegmentTracingMeasurements"
	endif	
	if (Wintype(traceResultsTableN) == 0)
		Edit/K=1/N=$traceResultsTableN
		traceResultsTableN = S_name		//in case naming fails
		tracing_showOpacitySlider()
	else		
		table_clear(traceResultsTableN)		//remove anything 
	endif
	
	Variable numStoredTraceParams = 7
	
	String tracedWaveIndexRef = tracing_getTracingIndexWaveRef(tracedWaveName)
	
	Variable numIndexCols = 3		//160330 increased to 3 from 2 to make room for user to show/hide a given segment
	
	WAVE/T/Z tracedWvIndex = $tracedWaveIndexRef
	String currTracingWaveName; variable i; string replacethisString,withThisString, oldName,newName
	Variable reallyOverwrite = 1, cancelButtonUsed		//user is prompted to set to 0 if NOT overwriting, which will abort
	if (!WaveExists(tracedWvIndex))
		Make/O/T/N=(1,numIndexCols)  $tracedWaveIndexRef	/wave =tracedWvIndex		//160330
		rowRequested = 0
	else
		WAVE/T tracedWvIndex = $tracedWaveIndexRef
		
		if (overwriteOrInsert)		//insert if true
			if (rowRequested > DimSize(tracedWvIndex,0) -1)			//insert before last
				rowRequested = DimSize(tracedWvIndex,0) -1
			elseif (rowRequested < 0)										//insert before first
				rowRequested = 0			
			endif
			
			//redimension, shift if necessary
			Redimension/N=(DimSize(tracedWvIndex,0)+1,-1) tracedWvIndex
			if (rowRequested <  DimSize(tracedWvIndex,0) -1)		//if not the last point anyway

				for (i=DimSize(tracedWvIndex,0)-1;i>rowRequested;i-=1)	//shift everything passed insertion point up one row
					tracedWvIndex[i][] = tracedWvIndex[i-1][q]
					replaceThisString = "_c"+num2str(i-1)
					withThisString = "_c"+num2str(i)
					oldName = tracedWvIndex[i][0]
					newName = replacestring(replaceThisString,tracedWvIndex[i][0],withThisString)
					tracedWvIndex[i][0] = newName
					SetDimLabel 0,i,$newName,tracedWvIndex
					if (WaveExists($oldName))
						Duplicate/O $oldname, $newname
					endif
				endfor
			endif		
		
		
		else			//overwrite
			if ( (rowRequested > DimSize(tracedWvIndex,0) -1) || (rowRequested < 0) )			//insert after last
				rowRequested = DimSize(tracedWvIndex,0)
				Redimension/N=(rowRequested+1,-1) tracedwvIndex
			else			//check whether user really wants to overwrite row
				prompt reallyOverwrite, "Overwrite seg " + num2str(rowRequested)
				doprompt "Overwrite seg (" + num2str(rowRequested) + ")? (0 or cancel button to abort)", reallyOverwrite
				cancelButtonUsed = V_flag		//generated by do prompt, 0 for ok, 1 for cancel		
				if ( (reallyOverwrite != 1) || cancelButtonUsed)
					Print "Overwrite of segment",rowRequested,"aborted by user input."
					return 0
				endif						
			
			endif
		endif
		
		//if not a new tracedWvIndex, save last pnt
		if (tracing_doPlot(winN))		//tracing in progress
			//tracing_saveCrossSectLastInWv()		//obsolete
		endif
	endif
		
	currTracingWaveName = tracedWaveName + "_c" + num2str(rowRequested)
	Make/O/N=(1,numStoredTraceParams) $currTracingWaveName/WAVE=currTracingWv
	currTracingWv = NaN
	String/G tracing_currTracingWaveName = currTracingWaveName
	tracedWvIndex[rowRequested][0] = tracing_currTracingWaveName
	tracedWvIndex[rowRequested][1] = SegmentNameStr
	tracedWvIndex[rowRequested][2] = "1"			//default is to show 
	SetDimLabel 0,rowRequested,$currTracingWaveName,tracedWvIndex
	
	tracing_updateZWave(tracedWaveName)
	String zPixelsWvRef = tracing_getZWaveRef(tracedWaveName)
	
	Print "new Segment added:" + tracing_currTracingWaveName +". (indexWv=" + tracedWaveIndexRef + ", zDispWv="+zPixelsWvRef+")"
	AppendToTable/W=$traceResultsTableN $tracing_currTracingWaveName, $tracedWaveIndexRef		//display on this table the current tracing measuremens and the index wave
	ModifyTable/W=$traceResultsTableN width($tracing_currTracingWaveName) = 40, width($tracedWaveIndexRef) = 60
	tracing_showSegTable_ref(tracedWaveName)//,0)
	doupdate;
	
	if (promptForRepeatPntOnFirstPnt && (rowRequested > 0) )
		Variable automaticallyRepeatLastPnt = 1
		String msgStr = "Repeat final point from last segment as first for new segment (recommended)?"
		prompt automaticallyRepeatLastPnt, msgStr
		doprompt msgStr, automaticallyRepeatLastPnt
		if (automaticallyRepeatLastPnt)
			tracing_repeatPoint(winN)
		endif
	endif
end



function/S tracing_getTracingIndexWaveRef(tracedwaveName)
	String tracedWaveName
	
	return  tracedWaveName + "_ind"
end

function/S tracing_getZWaveRef(tracedWaveName)
	STring tracedWaveName
	
	return tracedWaveName + "_z"
end

function/S tracing_getOverlayWvRef(tracedWaveName)
	String tracedWaveName
	
	return tracedWaveName + "_OL"
end

function/S tracing_getOverlayColorsWvRef(tracedWaveName)
	String tracedWaveName
	
	return tracedWaveName + "_OLC"
end

function/S tracing_getOverlayMarkerWvRef(tracedWaveName)
	String tracedWaveName
	
	return tracedWaveName + "_OLM"
end

function/S tracing_getCombinedSegref(tracedWaveName)
	STring tracedWaveName

	return tracedWaveName + "_cc"
end

function/s tracing_getCombinedSegRefTableN(combinedSegRef)
	string combinedSegRef
	
	String savedName = stringbykey("display_table_name",note($combinedSegRef))
	
	if (strlen(savedName))
		return savedName
	else
		return combinedSegRef + "tab"
	endif
end


function tracing_edgeAndImageToColor(edgeImgRef, origImgRef, outRef)
	String edgeImgRef, origImgRef, outRef
	
	WAVE origWv = $origImgRef
	WAVE edgeWv = $edgeImgRef
	
	Duplicate/O edgeWv, $outRef
	WAVE outWv = $outRef
	
	Redimension/N=(DimSize(origWv,0), DimSize(origWv, 1), 3, DimSize(origWv,2)) outWv
	outWv[][][0,1][] = edgeWv[p][q][s]	//edge wave to layers 0 and 1 (r and g guns)
	outWv[][][2][] = origWv[p][q][s]	//origin wave to layer 2 (blue gun)
	
	
//Duplicate/O tiffb, tiffChunks
//Redimension/N=(DimSize(tiffb,0), DimSize(tiffb,1), 3, DimSize(tiffb,2)) tiffChunks
//tiffChunks[][][0,1][] = tiffb[p][q][s]	
//tiffChunks[][][2][] = tiffc[p][q][s]	

end

function disp_isTraceHidden(winN, traceN)
	String winN, traceN
	
	if (strlen(winN) == 0)
		winN = winname(0,1) //top graph default
	endif
	
	return str2num(StringByKey("hideTrace(x)", traceinfo(winN, traceN, 0),"="))

end
	
function img_scroll(s)
	STRUCT WMWinHookStruct &s
	//if ((s.eventMod & 2^1) != 0)		// Shift
	//if ((s.eventMod & 2^3) != 0)		// control down
	
	Variable slowUnit = 1/8		//slow is one frame per scroll. igor7: wheel.dy is 6 not 1. Igor8 or home, it's 8
	Variable fastUnit = 1		//fast frames per scroll
	
	if ( (s.eventCode != 22) || ((s.eventMod & 2^3) != 0))		//must be scroll WITHOUT control down
		return 0
	endif
	
	Variable step = s.wheelDy
	//print "step",step
		
	if  ((s.eventMod & 2^1) != 0)		//shift down, go faster
		step *= fastUnit
	else
		step *= slowUnit
	endif
	
	step = floor(step)		//laptop scroll can be 3 or more than 3 if you swipe faster
	
	img_setDisplayedPlane(s.winName, img_getDisplayedPlane(s.winName) + step)
end

function img_checkSliderStatus()
	//may have to open an image for this to compile in igor 7. image package option not availableim
//	WMAppend3DImageSlider()		//does nothing if already there, creates subfolders etc for images if not there
	//either commentize above or go to analysis -> packages -> image processing and load that image processing package
end

function/S img_getImageName(winN)
	String winN
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
		
	String dfSav= GetDataFolder(1)		//store current data folder, return to here after executing function
	String target_df = "root:Packages:WM3DImageSlider:"+winN
	if (DataFolderExists(target_df))
		SetdataFolder $target_df			//set to the data folder for this window
	else
		df_makeFolder(target_df,inf)		//make data folder and set to last subdirectory
	endif
	 
	SVAR/Z imageName
	
	if (!Svar_exists(imageName) || !strlen(imageName) || !WaveExists($imageName))
		setDataFolder dfSav		//have to have global view for access to waves?
		String allWaves = wavelist("*",";","WIN:"+winN)
		String myWave = stringfromlist(0,allwaves)
		setdatafolder target_df
		String/G imageName = myWave
	endif
	
	SetDataFolder dfSav		//returns data folder back to whatever it was
	return imageName
end


function img_getDisplayedPlane(winN)
	String winN
	
	img_checkSliderStatus()

	String dfSav= GetDataFolder(1)
	SetDataFolder root:Packages:WM3DImageSlider:$(winN)
	NVAR/Z gLayer
	if (!NVAR_Exists(gLayer))
		Variable/G gLayer = 0
	endif

	SetDataFolder dfSav		//returns data folder back to whatever it was
	return gLayer
end

function img_setDisplayedPlane(winN, layer)
	String winN; Variable layer
	
	img_checkSliderStatus()

	String dfSav= GetDataFolder(1)
	SetDataFolder root:Packages:WM3DImageSlider:$(winN)
	NVAR gLayer
	
	gLayer = layer
//	String imageName = img_getImageName(winN)
//	ModifyImage/w=$winN  $imageName plane=(gLayer)	

	String images = ImageNameList(winN,";" )
	variable i
	for (i=0;i<itemsinlist(images);i+=1)
		ModifyImage/W=$winN $StringFromList(i,images) plane=(gLayer)	
	endfor
	
	

	SetDataFolder dfSav		//returns data folder back to whatever it was	
	return gLayer
end

//when enabled, zooms into plot at cursor based on two primary axes, which are assumed to be top for horizontal and left for vertical, maintains aspect ratio
function img_zoomHook(s)
	STRUCT WMWinHookStruct &s
	//Print "here"
	if ( (s.keycode < 6) || (s.keycode > 252))		//0 is no key, 1 is mouse scroll, and 254 255 is mouse scroll
		return 0		//ignore non-keyboard use
	endif
	
	return 0		//disabled for now
	
//	Print "key code. keycode = " + num2str(s.keycode)
	
	Variable zoomInNotOut, resetView
	if (s.keyCode == 43)		//+ with shift, determined empirically)
		zoomInNotOut = 1
	elseif (s.keycode == 95)
		zoomInNotOut = 0
	elseif (s.keycode == 41)		//shift zero key
		resetView = 1
	else
		return 0
	endif
	
	String horizAxName = "top"
	String vertAxName = "left"
	String winN= s.winName
	
	Variable zoomFoldChange = .25		//if .25, viewing range gets 25% smaller for zoomInNotOut true, or 25% large for zoomInNotOut false
	Variable changeRatio = zoomInNotOut ? 1 - zoomFoldChange : 1 + zoomFoldChange
	Print "changeRatio",changeRatio
	
	if (resetView)
		img_resetView(winN)
		return 1
	endif
	
	Variable xMousePixel = disp_getMouseLoc(s, horizAxName)	
	Variable yMousePixel = disp_getMouseLoc(s, vertAxName)
	
	GetAxis/Q/W=$winN $horizAxName
	Variable horizCurrStart = V_min
	Variable horizCurrEnd = V_max
	Variable horizFlipped = V_min > V_max
	Variable horizCurrMin = horizFlipped ? horizCurrEnd : horizCurrStart
	Variable horizCurrMax = horizFlipped ? horizCurrStart : horizCurrEnd
	
	Variable horizRange = (horizCurrMax - horizCurrMin) * changeRatio
	Variable horizNewMin =  (xMousePixel - horizRange/2)
	Variable horizNewMax = (xMousePixel + horizRange/2)
	
	GetAxis/Q/W=$winN $vertAxName
	Variable vertCurrStart = V_min
	Variable vertCurrEnd = V_max
	Variable vertFlipped = V_min > V_max
	Variable vertCurrMin = vertFlipped ? vertCurrEnd : vertCurrStart
	Variable vertCurrMax = vertFlipped ? vertCurrStart : vertCurrEnd
	
	Variable vertRange = (vertCurrMax - vertCurrMin) * changeRatio
	Variable vertNewMin =  (xMousePixel - vertRange/2)
	Variable vertNewMax = (xMousePixel + vertRange/2)
	
	if (zoomInNotOut)		//if zooming off to side, then zooming can bring out of viewed window, so check not to do that
		if (horizNewMin < horizCurrMin)
			horizNewMin = horizCurrMin
		endif
		if (horizNewMax > horizCurrMax)
			horizNewMax = horizCurrMax
		endif
		if (vertNewMin < vertCurrMin)
			vertNewMin = vertCurrMin
		endif
		if (vertNewMax > vertCurrMax)
			vertNewMax = vertCurrMax
		endif
	endif
	
	if (!horizFlipped)
		SetAxis/W=$winN top, horizNewMin, horizNewMax
	else
		SetAxis/W=$winN top, horizNewMax, horizNewMin
	endif
	
	if (!vertFlipped)
		SetAxis/W=$winN left, vertNewMin, vertNewMax
	else
		SetAxis/W=$winN left, vertNewMax, vertNewMin
	endif
	
	return 1		
	
end

function 	img_resetView(winN)
	String winN
	
	String imgWvRef = img_getImageName(winN)
	
	Variable xMax = DimSize($imgWvRef,0)
	Variable yMax = Dimsize($imgWvRef,1)
	
	SetAxis/W=$winN top, 0, xMax
	SetAxis/W=$winN left, yMax, 0		//default is flipped
end

function wave_4d_extractLayer(inRef, outRef, layerNum)
	String inRef, outRef; Variable layerNum
	
	Variable tempWvGenerated
	if (!stringmatch(inRef, outRef))	//safe to do everything "in place", in outRef, since outRef is not the same as inRef
		Duplicate/O $inRef, $outRef		//use duplicate instead of make to carry over wave type (e.g. float or integer)
		tempWvGenerated = 0
		WAVE inWv = $inRef
	else			//since outRef IS inRef, need to store the result somewhere else during computation so that outRef is not overwritten
		Duplicate/O $inRef, tempWv_literalName, $outRef
		tempWvGenerated = 1
		WAVE inWv = tempWv
	endif
	WAVE outWv = $outRef
	
	Redimension/N=(DimSize(inWv,0), DimSize(inWv,1), DimSize(inWv,3)) outWv
	outWv[][][] = inWv[p][q][layerNum][r]
	
	if (tempWvGenerated)
		KillWaves/Z tempWv_literalName
	endif
end

function img_thresholdLayers(origRef, displayedRef, saveWindows, rStartProp, rEndProp, rGamma, gStartProp, gEndProp, gGamma, bStartProp, bEndProp, bGamma)
	String origRef, displayedRef		//suggested to keep orig ref untouched, display displayed ref, which is a thresholded (DIRECTLY MODIFIED) version of origRef
	Variable saveWindows		//if passed, windows (min, max, scale factor) stored in lastLayerWindows
	Variable rStartProp, rEndProp, gStartProp, gEndProp, bStartProp, bEndProp		//threshold levels by proportion for each color
	Variable rGamma, gGamma, bGamma		//gamma correction values 
	
	Variable minVal = 0, maxVal = 65535	//this is the case for my waves so far, I think that's for 16 bit unsigned integer maybe? Color RGB might change that
	Variable fullRange = maxVal - minVal	//each layer will be scaled to this
	
	if (stringmatch(origRef, displayedRef))
		Print "Warning, function img_thresholdLayers() will not allow you to overwrite the original wave as data may be lost"
		return 0
	endif
	
	Variable k, numLayers = DimSize($origRef, 2)
	if (saveWindows)
		Make/O/D/N=(numLayers,4) lastLayerWindows
	endif

	Variable usedMin, usedMax, usedScaleFactor, usedGamma
	
	for (k=0;k<numLayers;k+=1)
		Print "starting layer = " + num2stR(k)
		if (k==0)
			usedGamma = rGamma
			img_thresholdLayer(origRef, displayedRef, 0, k, rStartProp, rEndProp, usedGamma, usedMin=usedMin,usedMax=usedMax, usedScaleFactor=usedScaleFactor)
		elseif (k==1)
			usedGamma = gGamma
			img_thresholdLayer(origRef, displayedRef, 1, k,  gStartProp, gEndProp, usedGamma, usedMin=usedMin,usedMax=usedMax, usedScaleFactor=usedScaleFactor)
		else	//k==2
			usedGamma = bGamma
			img_thresholdLayer(origRef, displayedRef, 1, k,  bStartProp, bEndProp, usedGamma, usedMin=usedMin,usedMax=usedMax, usedScaleFactor=usedScaleFactor)
		endif
		if (saveWindows)
			lastLayerWindows[k][0] = usedMin; lastLayerWindows[k][1] = usedMax; lastLayerWindows[k][2] = usedScaleFactor; lastLayerWindows[k][3] = usedGamma; 	//store used values
		endif
	endfor
	
	if (saveWindows)
		Print "layerWindows saved in waveRef = " + nameofwave(lastLayerWindows)
	endif
end

function img_applyLayerThresholds(origRef, displayedRef, layerWindowsRef)
	String origRef, displayedRef, layerWindowsRef
	
	Variable k, numLayers = DimSize($origRef, 2)
	for (k=0;k<numLayers;k+=1)
		Print "in img_applyLayerThresholds. starting layer = " + num2str(k)
		if (k==0)
			img_applyLayerThreshold(origRef, displayedRef, 0, k, layerWindowsRef)		//start afresh from original wave for first layer
		else
			img_applyLayerThreshold(origRef, displayedRef, 1, k, layerWindowsRef)		//then work with displayed wave to keep progress instead of overwriting it
		endif
	endfor
end

function img_applyLayerThreshold(origRef, displayedRef, useDisplayedRef, layer, layerWindowsRef)
	String origRef, displayedRef; Variable layer
	Variable useDisplayedRef	
	String layerWindowsRef	//as generated by img_thresholdLayers()
	
	Variable minVal = 0, maxVal = 65535
	
	WAVE/D layerWindowsWv = $layerWindowsRef

	if (!useDisplayedRef)
		Duplicate/O $origRef, $displayedRef		//last is a placeholder, better to dup and redimension then to make from scratch bc wavetype will be conserved
		WAVE origWv = $origRef; WAVE dispWv = $displayedRef
	else
		WAVE origWv = $displayedRef; WAVE dispWv = $displayedRef	//assignment statement will be performed in place, preserving displayedRef otherwise
	endif
	
	dispWv[][][layer][] = wave_valueThreshold(dispWv[p][q][layer][s], layerWindowsWv[layer][0], layerWindowsWv[layer][1], layerWindowsWv[layer][2], minVal, maxVal, 0, 1, layerWindowsWv[layer][3])
	//dispWv[][][layer][] = wave_valueThreshold(dispWv[p][q][layer][s], adjustedLayerMin, layerScaleFactor, minVal, maxVal, 0, 1)
end

function img_thresholdLayer(origRef, displayedRef, useDisplayedRef, layer, firstPixValProp, lastPixValProp, gammaVal, [usedMin, usedMax, usedScaleFactor])
	String origRef, displayedRef; Variable layer
	Variable firstPixValProp		//proportion for first pixel. e.g. 0.1 will exclude lowest 10% of pixel values. negative values should be ok, e.g. -0.1 will set min to 10% beyond min
	Variable lastPixValProp		//e.g. 0.9 will exclude highest 10%. values greater than one should be ok, e.g. 1.1 will set max to 10% ABOVE max value. sizes relative to range 
		//firstPix val must be less than lastpixval, both have to be within range of 0 to maxPixelValue
	Variable useDisplayedRef		//pass to avoid overwriting work on previous layers, e.g. in a loop through all the layers, first time pass 0 to begin anew, then pass 1
	Variable gammaVal			//1 for no correction

	Variable &usedMin, &usedMax, &usedScaleFactor		//pass BY REF to save used values

	Variable minVal = 0, maxVal = 65535	//this is the case for my waves so far, I think that's for 16 bit unsigned integer maybe? Color RGB might change that
	Variable fullRange = maxVal - minVal		//this full range will always be used
	
	if (firstPixValProp > lastPixValProp)
		Print "img_thresholdLayer(...) cannot take firstPixValProp > lastPixValProp. no thresholding performed"
		return 0
	endif
	
	if (stringmatch(origRef, displayedRef))
		Print "Warning, function img_thresholdLayers() will not allow you to overwrite the original wave as data may be lost"
		return 0
	endif
	if (!useDisplayedRef)
		Duplicate/O $origRef, $displayedRef		//last is a placeholder, better to dup and redimension then to make from scratch bc wavetype will be conserved
		WAVE origWv = $origRef; WAVE dispWv = $displayedRef
	else
		WAVE origWv = $displayedRef; WAVE dispWv = $displayedRef	//assignment statement will be performed in place, preserving displayedRef otherwise
	endif
	
	wave_4d_extractLayer(origRef, "layerTemp", layer)
	WAVE layerTemp
	Variable layerMin = wavemin(layerTemp)
	Variable layerMax = wavemax(layerTemp)
	Variable layerMean = mean(layerTemp)
	Variable layerRange = layerMax - layerMin
	Variable adjustedLayerMin = floor(layerMin + layerRange*firstPixValProp)		//keeps these as integers 
	//threshold so that 
	if (adjustedLayerMin < 0)
		adjustedLayerMin = 0
	endif
	Variable adjustedLayerMax = ceil(layerMin + layerRange*lastPixValProp)
	if (adjustedLayerMax > maxVal)
		adjustedLayerMax = maxVal
	endif
	Variable adjustedLayerRange = adjustedLayerMax - adjustedLayerMin
	
	Variable layerScaleFactor = fullRange / adjustedLayerRange		//what value to multiply by to make layerRange = fullRange
	dispWv[][][layer][] = wave_valueThreshold(dispWv[p][q][layer][s], adjustedLayerMin, adjustedLayerMax, layerScaleFactor, minVal, maxVal, 0, 1, gammaVal)


	//dispWv[][][layer][] = (dispWv[p][q][layer][s] - adjustedLayerMin) * layerScaleFactor
	if (!ParamIsDefault(usedMin))
		usedMin = adjustedLayerMin
	endif
	if (!ParamIsDefault(usedMax))
		usedMax = adjustedLayerMax
	endif
	if (!ParamIsDefault(usedScaleFactor))
		usedScaleFactor = layerScaleFactor
	endif
	
			//offsets values in layer to have lowest at zero, then multiplies by scale factor
	Print "layer = " + num2str(layer) + "origMin=" + num2str(layerMin) + ". origMax=" + num2str(layerMax) + ". range=" + num2str(layerRange) + ". mean=" + num2str(layerMean)+ "adjustedLayerMin = " + num2str(adjustedLayerMin) + "adjustedLayerMax = " + num2str(adjustedLayerMax) + "(adjustedLayerRange=" + num2str(adjustedLayerRange) +")"

end


function img_updateHist(new, autoRange, [newMinPixelVal, newMaxPixelVal, gammaVal])
	Variable new		//1 to start a new histogram
	Variable autoRange	//range is min pixel to max pixel
	Variable newMinPixelVal, newMaxPixelVal, gammaVal
	
	NVAR/Z img_minThreshold, img_maxThreshold	//set below if not existing
	
	if (new)
		String/G histImageWinRef = winname(0,1)
		String/G histImageRef = img_getImageName(histImageWinRef)	
		String/G histWinN = histImageRef + "_imgH"
		String/G histWvRef = histImageRef + "imgH_win"
		String/G gammaWvRef = histImageRef + "imgH_g"
	else
		SVAR histImageWinRef, histImageRef, histWinN, histWvRef, gammaWvRef
		doWindow/F $histImageWinRef;doupdate/W=$histImageWinRef	//bring image win to top, some functions only work with it on top
	endif
	
	Variable numBins = 500
	//can check that a wave is 16 bin unsigned: wavetype(w) & 0x20, returns >0 for 16 bit;  wavetype(w) & 0x40 returns >0 for unsigned. Max val is then 2^16 = 65536
	Variable maxDispVal = 2^16
	Variable minDispVal = 0
	Variable binWidth = (maxDispVal-minDispVal) / numBins
	
	if (!WaveExists($gammaWvRef) || new)
		if (ParamIsDefault(gammaVal))
			gammaVal = 1		//linear default
		endif		//otherwise gamma val is already passed and defined 
		Make/O/D/N=10000 $gammaWvRef
		SetScale/P x, 0, 1/10000, $gammaWvRef
		WAVE/D gammaWv = $gammaWvRef
		gammaWv = x^gammaVal
		doWindow/F $histImageWinRef;doupdate/W=$histImageWinRef; ModifyImage/W=$histImageWinRef $histImageRef, lookup=$gammaWvRef
	else
		if (!ParamIsDefault(gammaVal))		//gamma wave may need update
			WAVE/D gammaWv = $gammaWvRef
			gammaWv = x^gammaVal
			Print "new gamma = " +num2str(gammaVal)
		endif
	endif
	
	doWindow/F $histImageWinRef;doupdate/W=$histImageWinRef; 
	
//	if (new)
		Variable isFrom3ColorWave = img_getDisplayedRegion("imgTempForHist", winN=histImageWinRef)	
//	endif
	Variable currMinPixelVal, currMaxPixelVal
	
	if(NVAR_Exists(img_minThreshold) && !new)
		img_minThreshold = ParamIsDefault(newMinPixelVal) ? img_minThreshold : newMinPixelVal
	else
		Variable/G img_minThreshold = ParamIsDefault(newMinPixelVal) ?  wavemin($"imgTempForHist") : newMinPixelVal
	endif
	
	if(NVAR_Exists(img_maxThreshold) && !new)
		img_maxThreshold = ParamIsDefault(newMaxPixelVal) ?  img_maxThreshold : newMaxPixelVal
	else
		Variable/G img_maxThreshold = ParamIsDefault(newMaxPixelVal) ? wavemax($"imgTempForHist")  : newMaxPixelVal
	endif	
	
	if (autoRange)
		currMinPixelVal =  wavemin($"imgTempForHist")
		currMaxPixelVal =  wavemax($"imgTempForHist") 
	endif
	Print "img thresholds",img_minThreshold,img_maxThreshold

	doWindow/F $histImageWinRef;doupdate/W=$histImageWinRef; ModifyImage/W=$histImageWinRef $histImageRef, ctab= {img_minThreshold,img_maxThreshold,Grays,0}
	
	Variable pixelIntensityRange = img_maxThreshold - img_minThreshold
		
	Make/O/D/N=1 $histWvRef
	histogram/B={minDispVal, binWidth, numBins} $"imgTempForHist", $histWvRef
	
	WAVE histWv = $histWvRef
	Variable histMax = wavemax(histWv)
	histWv /= histMax
	
	if (wintype(histWinN) == 0)
		Display/K=1/N=$histWinN $histWvRef
		histWinN = S_name
		
		SetWindow $histWinN, hook(updateImgByHistHook)  = 	img_histAdj_winHook
		AppendtoGraph/W=$histWinN/L=L_gamma $gammaWvRef
		ModifyGraph/W=$histWinN freepos=0, lblpos=52
		ModifyGraph/W=$histWinN tick(L_gamma)=3,noLabel(L_gamma)=2, freePos(L_gamma)=500
		
		//fill gamma wave to bottom
		ModifyGraph/W=$histWinN mode($gammaWvRef)=7,usePlusRGB($gammaWvRef)=1,hbFill($gammaWvRef)=6
		ModifyGraph/W=$histWinN useNegPat($gammaWvRef)=1,plusRGB($gammaWvRef)=(16384,65280,16384)
		ReorderTraces/W=$histWinN  $histWvRef,{$gammaWvRef}		//put histogam ahead so it can be seen above fill
	
		Label/W=$histWinN bottom "Pixel value\\U (Histogram)\r\\Z08\\f01SHIFT\\f00: Set lower threshold, \\f01CTRL+SHIFT\\f00: Set upper threshold (by horizontal mouse position)\r\\f01CTRL\\f00 alone=Set gamma (by vertical mouse position)"
	endif
	ModifyGraph/W=$histWinN offset($gammaWvRef)={img_minThreshold,0}, muloffset($gammaWvRef)={pixelIntensityRange,0}
	doWindow/F $histImageWinRef;doupdate/W=$histImageWinRef; 
end

function img_histAdj_winHook(s)
	STRUCT WMWinHookStruct &s

	if (s.eventCode != 3)	//mouse not down
		return 0
	endif		//alt down
	//now have normal mouse events only
	
	if ( ((s.eventMod & 2^2) != 0))		//alt not allowed
		return 0
	endif
	
	Variable mouseAxisLoc 
	if (  ((s.eventMod & 2^3) != 0)	&& ((s.eventMod & 2^1) == 0) )	//cntl down without shift
		mouseAxisLoc = disp_getMouseLoc(s, "L_gamma")	//between 0 and 1
		img_updateHist(0,0,gammaVal=mouseAxisLoc/0.5)
		return 0
	endif
	

	mouseAxisLoc = disp_getMouseLoc(s, "bottom")
	
	if ((s.eventMod & 2^1) != 0)		//shift key, adjust left hist region
		if ((s.eventMod & 2^3) == 0)		//ctrl down WITHOUT shift key -- set lower range
			img_updateHist(0,0,newMinPixelVal=mouseAxisLoc)
			return 0
		else	
			img_updateHist(0,0,newMaxPixelVal=mouseAxisLoc)
			return 0
		endif
	endif	
	
//	img_updateHist(0,0,newMinPixelVal=mouseAxisLoc)
	
end

function img_getDisplayedRegion(outRef, [winN])
	String outRef, winN
	
	if (ParamIsDefault(winN))
		winN = winname(0,1)
	else
		doWindow/F $winN; doupdate/W=$winN
	endif
	
	String imgName = img_getImageName(winN)
	Variable zPlaneNum = img_getDisplayedPlane(winN)
	
	Variable xFlipped=0, yFlipped=0, xMin, xMax, yMin, yMax
	GetAxis/W=$winN top
	if (V_max < V_min)
		xFlipped = 1
		xMin = V_max; xMax = V_min
	else
		xMin = V_min; xMax = V_max
	endif
	GetAxis/W=$winN left
	if (V_max < V_min)
		xFlipped = 1
		yMin = V_max; yMax = V_min
	else
		yMin = V_min; yMax = V_max
	endif	
	
	Variable isFrom3ColorWave
	
	if (DimSize($imgName,3) > 1)	//then 4D wave with layers as colors
		Duplicate/O/R=[xMin, xMax][yMin,yMax][][zPlaneNum] $imgName, $outRef
		isFrom3ColorWave = 1
	else		//3D wave with layers as different z planes
		if (dimsize($imgName,2) == 0)		//2D image, no layers
			Duplicate/O/R=[xMin, xMax][yMin,yMax] $imgName,$outRef
		else
			Duplicate/O/R=[xMin, xMax][yMin,yMax][zPlaneNum] $imgName, $outRef
		endif
		isFrom3ColorWave = 0
	endif
	
	return isFrom3ColorWave
end

function img_redisplayView()
	String/G redisplayImgName = "img_redisplayRef"		//holds redisplay wave that is actually displayed
	String/G redisplayImgOrigName = "img_redisplayRef_orig"	//holds redisplay wave original, basis for modifications, untouched but used for calculations


	img_getDisplayedRegion(redisplayImgName)
	Duplicate/O $redisplayImgName, $redisplayImgOrigName	
	NewImage/K=1/N=$redisplayImgName $redisplayImgName
	String/G redisplayImgWinName = S_name
end

//this version of tracing_calcParams requires tracing window to be top window (other than command line window) at time of use
//this started out exactly like the standard tracing_calcParams but has been modified to allow pipette inputs
//and there's not the same support for naming/renaming and saving to stream
function tracing_calcParams_P(winSizeIs1XNot2X,z,dispResultsTable,somaPip_ccPnt,pedPip_ccPnt_fromEnd,hasOS,forceBaseName)
	Double winSizeIs1XNot2X		//0 for 2x, 1 for 1x, 2 for one 510 value, otherwise enter the value, if near an integer number be wary of rounding
	Variable dispResultsTable
	Variable somaPip_ccPnt		//pnts from start at which soma pipette was placed e.g. 0 for on inner segment end
	Variable pedPip_ccPnt_fromEnd		//pnts from end at which ped pipette was placed e.g. 0 for on terminal end
	Variable hasOS					//pass if has an OS segment, in which case a placeholder is not added
	String forceBaseName		//see tracing_calcParams_explicit2 parameter of same name
	Double z// = 2.2315431//0.4//0.4503956//0.3980472// nan		//had been a passed parameter: optionally pass z step depth to set other than 1, pass nan to avoid	
	
	String streamTags = ""
	String nameBase	= ""		//for saving to analysis stream. should be cell name. Only used if calcVersion = 1
	String oldNameToReplaceWithNameBase = ""		//if image had a generic name like "main", pass that generic name to have it replaced by nameBase	
	
	Variable savetostream = 0
		
	String nameBaseSaveAppendStr = "_img"
	
	String tracedWaveName = tracing_getTracedWvNameFromWin()
	String tracingIndexRef = tracing_getTracingIndexWaveRef(tracedWaveName)
	String combinedSegsRef = tracing_getCombinedSegref(tracedWaveName)
	
	if (strlen(nameBase) < 1)
		nameBase = tracedWaveName
	endif
	
	String linearParamsRef
	
	Variable micronsPerPixel
	String paramsRef = tracing_calcParams_explicit2(tracingIndexRef, winSizeIs1XNot2X,z,nan,nan,forceBaseName,out_micronsPerPixel=micronsPerPixel)
	String img_loadPath = stringbykey("img_loadPath",note($tracedWaveName)); note/nocr $paramsRef, "img_ref:"+tracedWaveName+";img_loadPath:"+img_loadPath+";"
	
	//make a linear version of the params ref; this will be different lengths for different cells if number of compartments differ
	linearParamsRef = paramsRef + "_L"
	WAVE paramsWv = $paramsRef
	Variable numParams = dimsize(paramsWv,0)
	Variable numSegs = dimsize(paramsWv,1)
	Variable linearParamNum = numParams * numSegs
	Make/O/D/N=(linearParamNum) $linearParamsRef/wave=linearParamsWv
	Variable i
	Variable segStartIndex
	String segLbl
	for (i=0;i<numSegs;i+=1)
		segLbl = GetDimLabel(paramsWv, 1, i) + "_"
		segStartIndex = i*numParams
		linearParamsWv[segStartIndex,segStartIndex+numParams-1] = paramsWv [p-segStartIndex][i] 
		dl_lblsToLbls(paramsRef,0,0,nan,linearParamsRef,0,segStartIndex,segLbl,1)
	endfor
	
	//make a version with added OS position
	String linearParams_pOSRef = linearParamsRef+"_pOS"
	Variable linearParamNum_pOS = hasOS ? linearParamNum : (linearParamNum+numParams)
	Make/O/D/N=(linearParamNum_pOS) $linearParams_pOSRef/wave=linearParamsWv_pOS
	Variable actSegNum
	
	if (hasOS)	
		for (i=0;i<numSegs;i+=1)
			segStartIndex = i*numParams
			actSegNum = i
			segLbl = GetDimLabel(paramsWv, 1, i) + "_"
			linearParamsWv_pOS[segStartIndex,segStartIndex+numParams-1] = paramsWv [p-segStartIndex][i] 
			dl_lblsToLbls(paramsRef,0,0,nan,linearParams_pOSRef,0,segStartIndex,segLbl,1)	
		endfor	
		
	else	
	
	
		for (i=0;i<(numSegs+1);i+=1)
			segStartIndex = i*numParams
			if (i==0)
				actSegNum = i
				segLbl = GetDimLabel(paramsWv, 1, actSegNum) + "_"
			elseif (i==1)
				segLbl = "os-s0_"
				linearParamsWv_pOS[segStartIndex,segStartIndex+numParams-1] = nan
				dl_lblsToLbls(paramsRef,0,0,nan,linearParams_pOSRef,0,segStartIndex,segLbl,1)	
				continue					
			else //i>1
				actSegNum = i-1
				segLbl = GetDimLabel(paramsWv, 1, actSegNum) + "_"
				segLbl = segLbl[0,strlen(segLbl)-3]+num2str(actSegNum)+"_"
			endif			
			linearParamsWv_pOS[segStartIndex,segStartIndex+numParams-1] = paramsWv [p-segStartIndex][actSegNum] 
			dl_lblsToLbls(paramsRef,0,0,nan,linearParams_pOSRef,0,segStartIndex,segLbl,1)		
		endfor	
			
	endif
	
	//store pipette positions
	redimension/N=(linearParamNum+2) linearParamsWv
	dl_assignAndLbl(linearParamsWv, linearParamNum, somaPip_ccPnt, "somaPip_ccPnt")
	dl_assignAndLbl(linearParamsWv, linearParamNum+1, pedPip_ccPnt_fromEnd, "pedPip_ccPnt_fromEnd")
	
	redimension/N=(linearParamNum_pOS+2) linearParamsWv_pOS
	dl_assignAndLbl(linearParamsWv_pOS, linearParamNum_pOS, somaPip_ccPnt, "somaPip_ccPnt")
	dl_assignAndLbl(linearParamsWv_pOS, linearParamNum_pOS+1, pedPip_ccPnt_fromEnd, "pedPip_ccPnt_fromEnd")
	
	//calculate params for total wave, with and without portions beyond pipettes lobbed off
	if (numtype(somaPip_ccPnt))		//make sure these are zero not nan
		somaPip_ccPnt=0
	endif
	if (numtype(pedPip_ccPnt_fromEnd))
		pedPip_ccPnt_fromEnd=0
	endif	
	String paramsRef_cc = tracing_calcParams_explicit2(tracingIndexRef, winSizeIs1XNot2X,z,somaPip_ccPnt,pedPip_ccPnt_fromEnd,forceBaseName)
	img_loadPath = stringbykey("img_loadPath",note($tracedWaveName)); note/nocr $paramsRef_cc, "img_ref:"+tracedWaveName+";img_loadPath:"+img_loadPath+";"
	
	//make a linear version of the params ref; this will be different lengths for different cells if number of compartments differ
	String linearParamsRef_cc = paramsRef_cc + "_Lc"
	WAVE paramsWv_cc = $paramsRef_cc
	numParams = dimsize(paramsWv_cc,0)
	numSegs = dimsize(paramsWv_cc,1)
	linearParamNum = numParams * numSegs
	Make/O/D/N=(linearParamNum) $linearparamsRef_cc/wave=linearparamsWv_cc
	for (i=0;i<numSegs;i+=1)
		segLbl = GetDimLabel(paramsWv_cc, 1, i) + "_"
		segStartIndex = i*numParams
		linearparamsWv_cc[segStartIndex,segStartIndex+numParams-1] = paramsWv_cc [p-segStartIndex][i] 
		dl_lblsToLbls(paramsRef_cc,0,0,nan,linearparamsRef_cc,0,segStartIndex,segLbl,1)
	endfor	
	
	concatenate/DL/NP=0 {$linearParamsRef_cc}, $linearParamsRef		//append combined params to linearized segment params
	concatenate/DL/NP=0 {$linearParamsRef_cc}, $linearParams_pOSRef		//append combined params to linearized segment params
	
	//transpose these for easy copying as one row (not one column)
	redimension/n=(-1,1) $linearParamsRef,$linearParams_pOSRef
	SetDimLabel 1,0,$namebase,$linearParamsRef,$linearParams_pOSRef 
	String linearParamsRef_T = linearParamsRef+"_T"
	Duplicate/O $linearParamsRef, $linearParamsRef_T
	MatrixTranspose $linearParamsRef_T
	String linearParams_pOSRef_T = linearParams_pOSRef+"_T"
	Duplicate/O $linearParams_pOSRef, $linearParams_pOSRef_T
	MatrixTranspose $linearParams_pOSRef_T
	
	if (dispResultsTable)
		edit/k=1 $paramsRef.ld,$linearParamsRef.ld,$linearParams_pOSRef.ld,$linearParamsRef_cc.ld
		edit/k=1 $linearParamsRef_T.ld
		edit/k=1 $paramsRef_cc.ld
		edit/k=1 $linearParams_pOSRef_T.ld
	endif
	
	String xdOutRef=nameBase+"_xd",segInfoRef=nameBase+"_segInfo"
	tracing_getDistStats(combinedSegsRef,micronsPerPixel,tracingIndexRef,xdOutRef,segInfoRef)
		
	Print "tracedWaveName",tracedWaveName,"tracingIndexRef",tracingIndexRef,"xdOutRef",xdOutRef,"segInfoRef",segInfoRef,"paramsRef",paramsRef,"linearParamsRef",linearParamsRef,"linearParamsRef_T",(tracingIndexRef+"_T"),"linearParams_pOSRef",linearParams_pOSRef,"linearParams_pOSRef_T",(linearParams_pOSRef+"_T")
	Print "paramsRef_cc",paramsRef_cc
	String noteStr = "tracing_nameBase:"+nameBase+";tracing_winSizeIs1XNot2X:"+num2str(winSizeIs1XNot2X)+";tracing_img_loadPath:"+img_loadPath+";tracing_expName:"+igorinfo(1)+";xdOutRef:"+xdOutRef+";segInfoRef:"+segInfoRef+";"
	note/nocr $paramsRef,noteStr
	note/nocr $linearParamsRef,noteStr
	note/nocr $linearParams_pOSRef,noteStr
	note/nocr $linearParamsRef_cc,noteStr
	note/nocr $linearParamsRef_T,noteStr
	note/nocr $linearParams_pOSRef_T,noteStr
	
	save/c/o/p=home $linearParams_pOSRef_T
	putscraptext linearParams_pOSRef_T
end

function tracing_getDistStats(combinedSegsRef,micronsPerPixel,tracingIndexRef,outref_xd,outRef_segInfo)
	String combinedSegsRef,tracingIndexRef,outref_xd,outRef_segInfo; Double micronsPerPixel
	print "micronsPerPixel",micronsPerPixel
	VAriable numSegs = dimsize($tracingIndexRef,0)
	//calculate dist,diam 
	wave ccWc = $combinedSegsRef
	duplicate/o ccWc,$outref_xd/wave=xd
	String segInfoLbls="segStartP;segEndP;segLenP;segStart_um;segEnd_um;segLen_um;"
	Variable numSegPArams=itemsinlist(segInfoLbls)
	make/o/d/n=(numSegs,numSegPArams) $outref_seginfo/wave=segInfo
	dl_assignLblsFromList(segInfo,1,0,segInfoLbls,"",0)
	setdimlabel 1,1,segName,$tracingIndexRef
	String segNames = wave_colList($tracingIndexRef,"segName","segName,*",0,"",1)
	dl_assignLblsFromList(segInfo,0,0,segNames,"",0)
	
	Variable startCol=dimsize(xd,1),rows=dimsize(xd,0),l=startCol-1,i
	Variable newPars=11
	Redimension/n=(-1,startCol+newPars) xd
	l+=1;setdimlabel 1,l,xMicronLoc,xd;xd[][%xMicronLoc]=xd[p][%xPixLoc]*micronsPerPixel
	l+=1;setdimlabel 1,l,yMicronLoc,xd;xd[][%yMicronLoc]=xd[p][%yPixLoc]*micronsPerPixel
	l+=1;setdimlabel 1,l,zMicronLoc,xd;xd[][%zMicronLoc]=xd[p][%zPixLoc]
	
	l+=1;setdimlabel 1,l,deltaDist_um,xd	//distance traversed between points
	xd[0][%deltaDist_um]=0
	xd[1,][%deltaDist_um]=sqrt(     ((xd[p][%xMicronLoc] - xd[p-1][%xMicronLoc])^2) + ((xd[p][%yMicronLoc] - xd[p-1][%yMicronLoc])^2) + ((xd[p][%zMicronLoc] - xd[p-1][%zMicronLoc])^2)     )
	//xd[1,][%deltaDist_um]=sqrt( ( (micronsPerPixel*(xd[p][%xPixLoc]-xd[p-1][%xPixLoc]))^2 ) + ( (micronsPerPixel*(xd[p][%yPixLoc]-xd[p-1][%yPixLoc]))^2 ) + ( (micronsPerPixel*(xd[p][%zPixLoc]-xd[p-1][%zPixLoc]))^ 2) )//xd[p][%deltaDist]*micronsPerPixel
	// (ccWv[p][xInd]-ccWv[p-1][xInd])^2 + (ccWv[p][yInd]-ccWv[p-1][yInd])^2 + (ccWv[p][zInd]-ccWv[p-1][zInd])^2 ) 
	
	l+=1;setdimlabel 1,l,dist_um,xd;	//total distance up to the start of this point
	xd[0][%dist_um]=0
	xd[1,][%dist_um]=xd[p-1][%dist_um]+xd[p][%deltaDist_um]		//first point has a delta dist of zero
	
	l+=1;setdimlabel 1,l,radius_um,xd
	xd[][%radius_um]=xd[p][%radiusPix]*micronsPerPixel
	
	l+=1;setdimlabel 1,l,diam_um,xd
	xd[][%diam_um]=xd[p][%radius_um]*2
	
	//segStartP;segEndP;segLenP;segStart_um;segEnd_um;segLen_um;"
	segInfo=nan
	segInfo[0][%segStartP]=0
	segInfo[0][%segStart_um]=0
	
	//find the start of each seg, then label all 
	l+=1;setdimlabel 1,l,firstRowInSeg,xd
	l+=1;setdimlabel 1,l,lastRowInSeg,xd
	Variable currSegNum=xd[0][%segNum],currFirstRow=0,segCount=0,lastPntInLastSeg		//segCount should always equal segNum but just in case of weirdness, will count separately too
	Variable pastLastPnt,iterEnd=rows+1		//need to go one extra round to deal with end of last segment
	for (i=0;i<iterEnd;i+=1)
		pastLastPnt = i==rows
		if (pastLastPnt || (xd[i][%segNum] != currSegNum)	)	//latter is for after last row
			lastPntInLastSeg=i-1	//i is in the next segment
				//finish info for last seg
			segInfo[segCount][%segEndP]=lastPntInLastSeg
			segInfo[segCount][%segLenP]=lastPntInLastSeg-segInfo[segCount][%segStartP]+1
			segInfo[segCount][%segEnd_um]=xd[pastLastPnt ? (i-1) : i][%dist_um]		//bit of an ambiguity whether to use last pnt or current -- in truth shouldnt matter if points are appropriately matched at ends
			segInfo[segCount][%segLen_um]=segInfo[segCount][%segEnd_um]-segInfo[segCount][%segStart_um]
			if (currFirstRow <= lastPntInLastSeg)	//if there is at least one cell to fill with last seg (pretty much always should be)
				xd[currFirstRow,lastPntInLastSeg][%lastRowInSeg] = i - 1
			endif
			if (pastLastPnt)
				break
			endif
				//fill info for next seg
			currSegNum=xd[i][%segNum]
			currFirstRow=i
			segCount+=1
			segInfo[segCount][%segStartP]=i
			segInfo[segCount][%segStart_um]=xd[i][%dist_um]
		endif
		xd[i][%firstRowInSeg]=currFirstRow
	endfor
		
	l+=1;setdimlabel 1,l,distInSeg_um,xd
	xd[][%distInSeg_um]=xd[p][%dist_um]-xd[xd[p][%firstRowInSeg]][%dist_um]
	
	l+=1;setdimlabel 1,l,distRelSeg,xd
	xd[][%distRelSeg]=xd[p][%distInSeg_um] / xd[xd[p][%lastRowInSeg]][%distInSeg_um]
end

function tracing_alignNrn(xNrnWv,xdWv,segInfoWv,imageDistXRef)	
	WAVE xNrnWv	//output from vxt_run in vxt_run.hoc, has sectionNums and sectionPositions (x) as columns, nodes as points
	WAVE xdWv,segInfoWv	//outputs from tracing_getDistStats, usually called by tracing_calcparams_p after tracing in Igor
	String imageDistXRef	//output of distances .. rows = nodes + 1 for rules of image x waves, last point is final point distance (just beyond last node)

	Variable i,nodes=dimsize(xNrnWv,0)
	String params = "dist_um;interpDiam_um;",param
	Variable numParams=itemsinlist(params),col
	for (i=0;i<numParams;i+=1)
		param=stringfromlist(i,params)
		if (finddimlabel(xNrnWv,1,param)<0)
			col=dimsize(xNrnwv,1)
			redimension/n=(-1,col+1) xNrnWv
			setdimlabel 1,col,$param,xNrnWv			
		endif
	endfor
	
	//need some single-column waves for interp
	duplicate/o/free/r=[][finddimlabel(xdWv,1,"dist_um")] xdwv,distWv;redimension/n=(-1) distWv
	duplicate/o/free/r=[][finddimlabel(xdWv,1,"diam_um")] xdwv,diamWv;redimension/n=(-1) diamWv
	
	
	Double xPosInSeg,segStart_um,segLen_um,dist_um
	Variable segNum
	for (i=0;i<nodes;i+=1)
		segNum=xNrNwv[i][%sectionNums]
		xPosInSeg=xNrNwv[i][%sectionPositions]
		segLen_um=segInfoWv[segNum][%segLen_um]	
		segStart_um=segInfoWv[segNum][%segStart_um]

		dist_um=segStart_um+xPosInSeg*segLen_um		
		xNrNWv[i][%dist_um]=dist_um
		xNrnWv[i][%interpDiam_um]=interp(dist_um,distWv,diamWv)
		
		setdimlabel 0,i,$getdimlabel(segInfoWv,0,segNum),xNrnWv
	endfor
	
	duplicate/o/r=[][finddimlabel(xNrNwv,1,"dist_um")] xNrnWv,$imageDistXRef/wave=xvals
	xvals[0]=0		//even though first node is usually at non zero because they are spaced throughout the segment, it looks better to plot from zero
	redimension/n=(nodes+1) xvals
	
	xvals[nodes]=distWv[dimsize(distWv,0)-1]

end

//OLD VERSION USE tracing_calcParams_P now
//this version of tracing_calcParams requires tracing window to be top window (other than command line window) at time of use
function tracing_calcParams(winSizeIs1XNot2X, nameBase, oldNameToReplaceWithNameBase, dispResultsTable,streamTags[z])
	Double winSizeIs1XNot2X			//0 for 60x2x, 1 for 60x1x, 2 for one 510 value, otherwise enter the value, if near an integer number be wary of rounding
	String nameBase			//for saving to analysis stream. should be cell name. Only used if calcVersion = 1
	String oldNameToReplaceWithNameBase		//if image had a generic name like "main", pass that generic name to have it replaced by nameBase
	Variable dispResultsTable
	String streamTags
	Double z		//optionally pass z step depth to set other than 1
		
	Variable calcVersion =1	//old or new format for params, new format (calcVersion = 1) is saved to an analysis stream
	
	String nameBaseSaveAppendStr = "_img"
	
	String tracedWaveName = tracing_getTracedWvNameFromWin()
	String tracingIndexRef = tracing_getTracingIndexWaveRef(tracedWaveName)
	String combinedSegsRef = tracing_getCombinedSegref(tracedWaveName)
	
	if (strlen(nameBase) < 1)
		nameBase = tracedWaveName
	endif
	
	String linearParamsRef
	
	if (calcVersion)
		nameBase = nameBase + nameBaseSaveAppendStr
		String paramsRef = tracing_calcParams_explicit2(tracingIndexRef, winSizeIs1XNot2X,!ParamIsDEfault(z) ? z : nan,nan,nan,"")
		String img_loadPath = stringbykey("img_loadPath",note($tracedWaveName))
		note/nocr $paramsRef, "img_ref:"+tracedWaveName+";img_loadPath:"+img_loadPath+";"
		
		//make a linear version of the params ref; this will be different lengths for different cells if number of compartments differ
		linearParamsRef = nameBase + "_L"
		WAVE paramsWv = $paramsRef
		Variable numParams = dimsize(paramsWv,0)
		Variable numSegs = dimsize(paramsWv,1)
		Make/O/D/N=(numParams*numSegs) $linearParamsRef/wave=linearParamsWv
		Variable i
		Variable segStartIndex
		String segLbl
		for (i=0;i<numSegs;i+=1)
			segLbl = GetDimLabel(paramsWv, 1, i) + "_"
			segStartIndex = i*numParams
			linearParamsWv[segStartIndex,segStartIndex+numParams-1] = paramsWv [p-segStartIndex][i] 
			dl_lblsToLbls(paramsRef,0,0,nan,linearParamsRef,0,segStartIndex,segLbl,1)
		endfor
		
		String linearParamsRef_T = linearParamsRef+"_T"
		Duplicate/O $linearParamsRef, $linearParamsRef_T
		MatrixTranspose $linearParamsRef_T
		
		//make a version with added OS position
		String linearParams_pOSRef = linearParamsRef+"_pOS"
		Make/O/D/N=(numParams*(numSegs+1)) $(linearParams_pOSRef)/wave=linearParamsWv_pOS
		Variable actSegNum
		for (i=0;i<(numSegs+1);i+=1)
			segStartIndex = i*numParams
			actSegNum = i
			if (i==1)
				//i == 0, insert OS
				segLbl = "os-s-1_"
				linearParamsWv_pOS[segStartIndex,segStartIndex+numParams-1] = nan
				dl_lblsToLbls(paramsRef,0,0,nan,linearParams_pOSRef,0,segStartIndex,segLbl,1)	
				continue			
			elseif (i>1)
				actSegNum = i-1
			endif
			
			segLbl = GetDimLabel(paramsWv, 1, actSegNum) + "_"
			linearParamsWv_pOS[segStartIndex,segStartIndex+numParams-1] = paramsWv [p-segStartIndex][actSegNum] 
			dl_lblsToLbls(paramsRef,0,0,nan,linearParams_pOSRef,0,segStartIndex,segLbl,1)	
		endfor	
		
		String linearParams_pOSRef_T = linearParams_pOSRef+"_T"
		Duplicate/O $linearParams_pOSRef, $linearParams_pOSRef_T
		MatrixTranspose $linearParams_pOSRef_T 
		
		WAVE linearTransposeWv = $linearParamsRef_T, linearTransposePOSWv = $linearParams_pOSRef_T
		
		//prepare for saving to analysis stream
		String paramsNote = note($paramsRef)
		String streamStr = "trace"
		String segmentList = replacestring(",",stringbykey("segmentList",paramsNote),";")
		String listOfRefsToSaveInPath = tracedWaveName+";"+tracingIndexRef+";"+paramsRef+";"+segmentList+";"+combinedSegsRef+";"
		if (strlen(oldNameToReplaceWithNameBase))
			String oldList = listOfRefsToSaveInPath

			listOfRefsToSaveInPath = wave_dupWithStrReplacedName(oldList, oldNameToReplaceWithNameBase, nameBase)
			String oldParamsNote = paramsNote
			paramsNote = replacestring(oldNameToReplaceWithNameBase,oldParamsNote,nameBase)
			Print "params note updated for new wave names. next lines are old then new"
			Print "oldParamsNote",oldParamsNote
			print "newparamsNote",paramsNote
		endif
		
		if (dispResultsTable)
			edit/k=1 $paramsRef.ld,$linearParamsRef.ld,$linearParams_pOSRef.ld
			edit/k=1 linearTransposeWv.ld
			edit/k=1 linearTransposePOSWv.ld
		endif
		
		Print "tracedWaveName",tracedWaveName,"tracingIndexRef",tracingIndexRef,"paramsRef",paramsRef,"linearParamsRef",linearParamsRef,"linearParamsRef_T",(tracingIndexRef+"_T"),"linearParams_pOSRef",linearParams_pOSRef,"linearParams_pOSRef_T",(linearParams_pOSRef+"_T")
	else
		tracing_calcParams_explicit(tracingIndexRef, winSizeIs1XNot2X)
	endif
end

function tracing_showSegTable(dispWinN,[winN])
	String dispWinN, winN
	
	String tracedWaveName
	if (!paramisDefault(winn))
		tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	else
		tracedWaveName = tracing_getTracedWvNameFromWin()		//use top win
	endif
	
	tracing_showSegTable_ref(tracedWaveName)//0)
	return 0
end

static constant k_doCcStats=1		//change this to zero if computation is slowing tracing updates
//tracing function that concatenates segment params into combined params
//relies on the accuracy of tracing_numParamCols
function tracing_showSegTable_ref(tracedWaveRef)
	String tracedWaveRef

	String tracingIndexRef = tracing_getTracingIndexWaveRef(tracedWaveRef)

	Variable tracing_numParamCols = 23
	Variable segRefCol = 0
		
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveRef)	
	WAVE/T/Z tracingIndexWv = $tracingIndexRef
	
	if (!WaveExists(tracingIndexWv))
		return 0
	endif
	
	tracing_updateCombinedSegRef(tracedWaveRef)
	
	String dispWinN = tracing_getCombinedSegRefTableN(combinedSegRef)
	if (wintype(dispWinN) == 0)
		table_clear(dispWinN)
		edit/k=1/N=$dispWinN
		dispWinN = S_name
		AppendToTable/W=$dispWinN $combinedSegRef.ld	
	endif
	note/nocr $combinedSegRef,"display_table_name:"+dispWinN+";"	//might only be necessary when window first created
	
	//calculate some additional stats that are helpful for display
	Variable numCcPnts=dimsize($combinedSegRef,0)
	if (k_doCcStats && (numCcPnts>1))
		WAVE ccWv=$combinedSegRef
		Variable origCcCols=dimsize(ccWv,1)		//depends on original segment wave layout
		Variable newCols = 3
		Variable distDeltaInd = origCcCols		//distDelta is euclidian distance since last point
		Variable distInd=origCcCols + 1			//dist is total euclidian distance since first point
		redimension/n=(-1,origCcCols+newCols) ccWv
		setdimlabel 1,distDeltaInd,deltaDist,ccWv	
		setdimlabel 1,	distInd,totalDist,ccWv
		Variable xInd = finddimlabel(ccWv,1,"xPixLoc")
		Variable yInd = finddimlabel(ccWv,1,"yPixLoc")
		Variable zInd = finddimlabel(ccWv,1,"zPixLoc")
		
		ccWv[0][distDeltaInd]=0;ccWv[0][distInd]=0;
		ccWv[1,][distDeltaInd]=sqrt( (ccWv[p][xInd]-ccWv[p-1][xInd])^2 + (ccWv[p][yInd]-ccWv[p-1][yInd])^2 + (ccWv[p][zInd]-ccWv[p-1][zInd])^2 )
		ccWv[1,][distInd]=ccWv[p][distDeltaInd]+ccWv[p-1][distInd]
	
		Variable segNumInd = origCcCols + 2
		setdimlabel 1,	segNumInd,segNum,ccWv
		ccWv[][segNumInd]=str2num(replacestring("c",stringfromlist(1,getdimlabel(ccWv,0,p),"_"),""))
	endif

//	Modifytable/W=$dispWinN topleftcell  = (dimsize($combinedSegRef,0)-5,0)
end

function/S tracing_updateCombinedSegRef(tracedWaveRef)
	String tracedWaveRef

	String tracingIndexRef = tracing_getTracingIndexWaveRef(tracedWaveRef)

	Variable tracing_numParamCols = 23
	Variable segRefCol = 0
		
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveRef)	
	WAVE/T/Z tracingIndexWv = $tracingIndexRef
	
	if (!WaveExists(tracingIndexWv))
		return ""
	endif
	
	Variable i,segLen; string segList = "", segRef
	for (i=0;i<dimsize(tracingIndexWv,0);i+=1)
		segRef = tracingIndexWv[i][segrefCol]
		if (WaveExists($segref))
			segLen = dimsize($segref,0)
				//currently have an error that is causing wrong indexing here, so just going to always redo for now
			//if (!strlen(GetDimLabel($segRef, 0, 0)) || !strlen(GetDimLabel($segRef, 0, segLen-1)))		//incomplete row dim labels, assign..this check could be more extensive
				dl_lblByInd(segRef,0,segRef+"_",1)
			//endif
			
			if (!strlen(GetDimLabel($segRef, 1, 0)))		//no column dim labels, assign
				tracing_setSegColumnsLbls(segref)
			endif		
			segList += tracingIndexWv[i][segrefCol] + ";"
		endif
	endfor
	concatenate/O/NP=0/DL segList, $combinedSegRef
	setscale/p x,0,1,"",$combinedSegRef

	return combinedSegRef
end

function tracing_setSegColumnsLbls(segref)
	String segRef
	
	if (!waveexists($segRef))
		return 0
	endif
	
	SetDimLabel 1,0,xPixLoc,$segRef
	SetDimLabel 1,1,yPixLoc,$segRef
	SetDimLabel 1,2,xPixNearest,$segRef
	SetDimLabel 1,3,yPixNearest,$segRef
	SetDimLabel 1,4,zPixLoc,$segRef
	SetDimLabel 1,5,radiusPnts,$segRef
	SetDimLabel 1,6,radiusPix,$segRef
end

//two output waves: segment params and total params (all segments)
//for each param: numpnts, displacement x, y, z, total; dist x,y,z, total; radius mean, min, max
//REPLACED BY tracing_calcParams_explicit2
function tracing_calcParams_explicit(tracingIndexRef, winSizeIs1XNot2X)
	String tracingIndexRef
	Double winSizeIs1XNot2X		
	
	Double micronsPerPixel_2X = 100/1050
	Double micronsPerPixel_1x = 100/510
	Double micronsPerPixel_lsm510_40x = 0.1124711
	Double micronsPerZStep = 1
	
	Double micronsPerPixel_used
	switch (winSizeIs1XNot2X)
		case 0:
			micronsPerPixel_used = micronsPerPixel_2x
			break
		case 1:
			micronsPerPixel_used = micronsPerPixel_1X
			break
		case 2:
			micronsPerPixel_used = micronsPerPixel_lsm510_40x
			break
		default:
			micronsPerPixel_used = micronsPerPixel_used
			break
	endswitch
	
	Print "micronsPerPixel_used", micronsPerPixel_used
	
	//micronsPerPixel_used = winSizeIs1XNot2X ? micronsPerPixel_1x : micronsPerPixel_2X
	
	Variable numParams = 12		//actual numParams is doubled to account for results in pixel units as well as in microns
	
	WAVE/T tracingIndex = $tracingIndexRef
	
	String segmentParamsOutRef = tracing_getTracedWvNFromIndRef(tracingIndexRef) + "_pS"		//params for segments
	String totalParamsOutRef = tracing_getTracedWvNFromIndRef(tracingIndexRef) + "_pT"	//params for total
	
	Print "storing results in ", segmentParamsOutRef, totalParamsOutRef, ". Use header:", tracing_getParamsHeader() 
	Print "To display copy: Edit/K=1 ", tracing_getParamsHeader(), ", ", totalParamsOutRef, ", ", segmentParamsOutRef
	
	Variable i, numSegs = DimSize(tracingIndex,0)
	
	Make/D/O/N=(numSegs, numParams*2) $segmentParamsOutRef; WAVE/D segParamsOut = $segmentParamsOutRef
	Make/D/O/N=(numParams*2) $totalParamsOutRef; WAVE/D totalParamsOut = $totalParamsOutRef
	
	totalParamsOut = 0		//instantiate so that each segment result can be added during loop
	String currSegRef
	Variable x_dist_pix, x_disp_pix, y_dist_pix, y_disp_pix, z_dist_pix, z_disp_pix
	Variable r_mean_pix, r_stdev_pix, r_min_pix, r_max_pix
	Variable total_disp_pix, total_dist_pix

	Variable x_dist_micron, x_disp_micron, y_dist_micron, y_disp_micron, z_dist_micron, z_disp_micron
	Variable r_mean_micron, r_stdev_micron, r_min_micron, r_max_micron
	Variable total_disp_micron, total_dist_micron

	for (i=0;i<numSegs;i+=1)
		currSegRef = tracingIndex[i][0]

		if (DimSize($currSegRef,0) < 2)	//sometimes segs might be empty or have only one point
									//e.g. if they were started but not filled (such as when deleted)
			continue			//skipping these as they contribute no length
		endif
		
		Duplicate/O/R=[][0] $currSegRef, currVals_x_pix, currVals_x_micron			//for x (this segment)
		Duplicate/O/R=[][1] $currSegRef, currVals_y_pix, currVals_y_micron	
		Duplicate/O/R=[][4] $currSegRef, currVals_z_pix, currVals_z_micron
		Duplicate/O/R=[][6] $currSegRef, currVals_rad_pix, currVals_rad_micron			//for radius
		
		currVals_x_micron = currVals_x_pix * micronsPerPixel_used
		currVals_y_micron = currVals_y_pix * micronsPerPixel_used
		currVals_z_micron = currVals_z_pix * micronsPerZStep
		currVals_rad_micron = currVals_rad_pix * micronsPerPixel_used
		
		//calculations for pixel units
		x_disp_pix = wavemax(currVals_x_pix) - wavemin(currVals_x_pix)
		x_dist_pix = wave_getTotalDist_1D("currVals_x_pix")

		y_disp_pix = wavemax(currVals_y_pix) - wavemin(currVals_y_pix)
		y_dist_pix = wave_getTotalDist_1D("currVals_y_pix")
	
		z_disp_pix = wavemax(currVals_z_pix) - wavemin(currVals_z_pix)
		z_dist_pix = wave_getTotalDist_1D("currVals_z_pix")
		
		total_disp_pix = sqrt(x_disp_pix^2 + y_disp_pix^2 + z_disp_pix^2)		//for this segment
		total_dist_pix = wave_getTotalDist_3D("currVals_x_pix","currVals_y_pix","currVals_z_pix")
		
		Wavestats/Q currVals_rad_pix
		r_mean_pix = V_avg
		r_stdev_pix = V_sdev
		r_min_pix = V_min
		r_max_pix = V_max
		
		//calculation for micron units
		x_disp_micron = wavemax(currVals_x_micron) - wavemin(currVals_x_micron)
		x_dist_micron = wave_getTotalDist_1D("currVals_x_micron")

		y_disp_micron = wavemax(currVals_y_micron) - wavemin(currVals_y_micron)
		y_dist_micron = wave_getTotalDist_1D("currVals_y_micron")
	
		z_disp_micron = wavemax(currVals_z_micron) - wavemin(currVals_z_micron)
		z_dist_micron = wave_getTotalDist_1D("currVals_z_micron")
		
		total_disp_micron = sqrt(x_disp_micron^2 + y_disp_micron^2 + z_disp_micron^2)		//for this segment
		total_dist_micron = wave_getTotalDist_3D("currVals_x_micron","currVals_y_micron","currVals_z_micron")
		
		Wavestats/Q currVals_rad_micron
		r_mean_micron = V_avg
		r_stdev_micron = V_sdev
		r_min_micron = V_min
		r_max_micron = V_max
		
		//store results (pixels)
		segParamsOut[i][0] = x_dist_pix
		segParamsOut[i][1] = x_disp_pix
		segParamsOut[i][2] = y_dist_pix
		segParamsOut[i][3] = y_disp_pix
		segParamsOut[i][4] = z_dist_pix
		segParamsOut[i][5] = z_disp_pix
		segParamsOut[i][6] = total_disp_pix
		segParamsOut[i][7] = total_dist_pix
		segParamsOut[i][8] = r_mean_pix	//for this segment
		segParamsOut[i][9] = r_stdev_pix
		segParamsOut[i][10] = r_min_pix
		segParamsOut[i][11] = r_max_pix		
		//store results (microns)		
		segParamsOut[i][numParams+0] = x_dist_micron
		segParamsOut[i][numParams+1] = x_disp_micron
		segParamsOut[i][numParams+2] = y_dist_micron
		segParamsOut[i][numParams+3] = y_disp_micron
		segParamsOut[i][numParams+4] = z_dist_micron
		segParamsOut[i][numParams+5] = z_disp_micron
		segParamsOut[i][numParams+6] = total_disp_micron
		segParamsOut[i][numParams+7] = total_dist_micron
		segParamsOut[i][numParams+8] = r_mean_micron	//for this segment
		segParamsOut[i][numParams+9] = r_stdev_micron
		segParamsOut[i][numParams+10] = r_min_micron
		segParamsOut[i][numParams+11] = r_max_micron				
		
		totalParamsOut += segParamsOut[i][p]	//add this to total sum	
		
	endfor
end


//two output waves: segment params and total params (all segments)
//for each param: numpnts, displacement x, y, z, total; dist x,y,z, total; radius mean, min, max 
function/S tracing_calcParams_explicit2(tracingIndexRef, winSizeIs1XNot2X,zStepDepth,somaPip_ccPnt,pedPip_ccPnt_fromEnd,forceBaseName,[out_micronsPerPixel])
	String tracingIndexRef
	Double winSizeIs1XNot2X		//0 for 2x, 1 for 1x, 2 for one 510 value, otherwise enter the value, if near an integer number be wary of rounding
	Double zStepDepth		//pass NaN to use default of 1
	String forceBaseName	//blank to autogenerate (usual, but this is helpful for long tracing wave names)
	
	//pass NaN for these if what is wanted is segment parameters; if somaPip_ccPnt is a real number this will 
	//calculate the parameters for the combined param only
	Variable somaPip_ccPnt		//pnts from start at which soma pipette was placed e.g. 0 for on inner segment end
	Variable pedPip_ccPnt_fromEnd		//pnts from end at which ped pipette was placed e.g. 0 for on terminal end
	Variable &out_micronsPerPixel		//optionally pass to return micronsPerPixel_used here
	
//	Variable micronsPerPixel_2x_numer = 100		//more accurate for saving than the resultant fraction
//	Variable micronsPerPixel_2x_denom = 1050
//	Variable micronsPerPixel_2X = micronsPerPixel_2x_numer/micronsPerPixel_2x_denom
//	Variable micronsPerPixel_1x_numer = 100
//	Variable micronsPerPixel_1x_denom = 510
//	Variable micronsPerPixel_1x = micronsPerPixel_1x_numer/micronsPerPixel_1x_denom
//	Variable micronsPerPixel_used = winSizeIs1XNot2X ? micronsPerPixel_1x : micronsPerPixel_2X
	
	Double micronsPerPixel_2X = 100/1050
	Double micronsPerPixel_1x = 100/510
	Double micronsPerPixel_lsm510_40x = 0.1124711
	Double micronsPerZStep = numtype(zStepDepth) ? 1 : zStepDepth
	
	Double micronsPerPixel_used
	if (winSizeIs1XNot2X==0)
		micronsPerPixel_used = micronsPerPixel_2x
	elseif (winSizeIs1XNot2X==1)
		micronsPerPixel_used = micronsPerPixel_1X
	elseif (winSizeIs1XNot2X==2)
		micronsPerPixel_used = micronsPerPixel_lsm510_40x
	else
		micronsPerPixel_used = winSizeIs1XNot2X	
	endif
	
	Print "micronsPerPixel_used", micronsPerPixel_used,"micronsPerZStep",micronsPerZStep
	
	if (!Paramisdefault(out_micronsPerPixel))
		out_micronsPerPixel = micronsPerPixel_used
	endif
	
	Variable calcSegParams = numtype(somaPip_ccPnt) != 0
		
	Variable numParams = 12		//actual numParams is doubled to account for results in pixel units as well as in microns
	
	WAVE/T tracingIndex = $tracingIndexRef
	String tracedWaveRef = tracing_getTracedWvNFromIndRef(tracingIndexRef)
	String combinedSegsRef = tracing_getCombinedSegref(tracedWaveRef)
	String paramsOutRef
	String baseName 
	if (strlen(forceBaseName) > 0)
		baseName = forceBaseName
	else
		baseName =tracedWaveRef
	endif
	Variable i,c,numSegs,numSegsInCalc=0,outNumCols
	if (calcSegParams)
		paramsOutRef = baseName + "_pTr"	//params for tracing
		numSegs = DimSize(tracingIndex,0)
		outNumCols = numSegs+1
	else
		paramsOutRef = baseName + "_pcTr"	//params combined for tracing	
		numSegs = 2
		outNumCols = numSegs
	endif
	
	Print "storing results in paramsOutRef", paramsOutRef
	
	Make/D/O/N=(numParams*2,outNumCols) $paramsOutRef; WAVE/D paramsWv = $paramsOutRef		//one column for totals, then one column for each segment
	paramsWv = 0	//instantiate so that each segment result can be added during loop
	
	String currSegRef, segNameStr
	Variable x_dist_pix, x_disp_pix, y_dist_pix, y_disp_pix, z_dist_pix, z_disp_pix
	Variable r_mean_pix, r_stdev_pix, r_min_pix, r_max_pix
	Variable total_disp_pix, total_dist_pix

	Variable x_dist_micron, x_disp_micron, y_dist_micron, y_disp_micron, z_dist_micron, z_disp_micron
	Variable r_mean_micron, r_stdev_micron, r_min_micron, r_max_micron
	Variable total_disp_micron, total_dist_micron
	Variable segAnalysisStartP,segAnalysisEndP
	
	SetDimLabel 1,0,paramTotals,paramsWv 	//label totals column
	String segList = ""
	
	for (i=0;i<numSegs;i+=1)
		if (calcSegParams)
			currSegRef = tracingIndex[i][0]; segList += currSegRef + ";"
			segNameStr = tracingIndex[i][1]
			
			c = i + 1		//c = paramWv column num. first column reserved for totals
			segAnalysisStartP = 0
			segAnalysisEndP = dimsize($currSegRef,0) - 1		//include up and including last point
		else
			currSegRef = combinedSegsRef; segList += currSegRef + ";"
			
			c = i		//c = paramWv column num
			if (i==0)		//first do the entire thing
				segNameStr = "total_"
				segAnalysisStartP = 0
				segAnalysisEndP = dimsize($currSegRef,0) - 1		//include up and including last point				
			else			//then do just between pipettes
				segNameStr = "inPips_"
				segAnalysisStartP = somaPip_ccPnt
				segAnalysisEndP = dimsize($currSegRef,0) - 1 - pedPip_ccPnt_fromEnd 
			endif
		endif
		

		if (DimSize($currSegRef,0) < 2)	//sometimes segs might be empty or have only one point
									//e.g. if they were started but not filled (such as when deleted)
			continue			//skipping these as they contribute no length
		endif
		numSegsInCalc += 1
		if (calcSegParams)
			SetDimLabel 1,c,$(segNameStr+"-s"+num2str(i)),paramsWv		//label segment column 
		else
			SetDimLabel 1,c,$segNameStr,paramsWv		//label segment column 
		endif
		
		Duplicate/O/R=[segAnalysisStartP,segAnalysisEndP][0] $currSegRef, currVals_x_pix, currVals_x_micron	//xPixLoc			//for x (this segment)
		Duplicate/O/R=[segAnalysisStartP,segAnalysisEndP][1] $currSegRef, currVals_y_pix, currVals_y_micron	//yPixLoc
		Duplicate/O/R=[segAnalysisStartP,segAnalysisEndP][4] $currSegRef, currVals_z_pix, currVals_z_micron	//zPixLoc
		Duplicate/O/R=[segAnalysisStartP,segAnalysisEndP][6] $currSegRef, currVals_rad_pix, currVals_rad_micron	//radiusPix			//for radius
		
		currVals_x_micron = currVals_x_pix * micronsPerPixel_used
		currVals_y_micron = currVals_y_pix * micronsPerPixel_used
		currVals_z_micron = currVals_z_pix * micronsPerZStep
		currVals_rad_micron = currVals_rad_pix * micronsPerPixel_used
		
		//calculations for pixel units
		x_disp_pix = wavemax(currVals_x_pix) - wavemin(currVals_x_pix)
		x_dist_pix = wave_getTotalDist_1D("currVals_x_pix")

		y_disp_pix = wavemax(currVals_y_pix) - wavemin(currVals_y_pix)
		y_dist_pix = wave_getTotalDist_1D("currVals_y_pix")
	
		z_disp_pix = wavemax(currVals_z_pix) - wavemin(currVals_z_pix)
		z_dist_pix = wave_getTotalDist_1D("currVals_z_pix")
		
		total_disp_pix = sqrt(x_disp_pix^2 + y_disp_pix^2 + z_disp_pix^2)		//for this segment
		total_dist_pix = wave_getTotalDist_3D("currVals_x_pix","currVals_y_pix","currVals_z_pix")
		
		Wavestats/Q currVals_rad_pix
		r_mean_pix = V_avg
		r_stdev_pix = V_sdev
		r_min_pix = V_min
		r_max_pix = V_max
		
		//calculation for micron units
		x_disp_micron = wavemax(currVals_x_micron) - wavemin(currVals_x_micron)
		x_dist_micron = wave_getTotalDist_1D("currVals_x_micron")

		y_disp_micron = wavemax(currVals_y_micron) - wavemin(currVals_y_micron)
		y_dist_micron = wave_getTotalDist_1D("currVals_y_micron")
	
		z_disp_micron = wavemax(currVals_z_micron) - wavemin(currVals_z_micron)
		z_dist_micron = wave_getTotalDist_1D("currVals_z_micron")
		
		total_disp_micron = sqrt(x_disp_micron^2 + y_disp_micron^2 + z_disp_micron^2)		//for this segment
		total_dist_micron = wave_getTotalDist_3D("currVals_x_micron","currVals_y_micron","currVals_z_micron")
		
		Wavestats/Q currVals_rad_micron
		r_mean_micron = V_avg
		r_stdev_micron = V_sdev
		r_min_micron = V_min
		r_max_micron = V_max
		
		//store results (pixels)
		paramsWv[0][c] = x_dist_pix
		paramsWv[1][c] = x_disp_pix
		paramsWv[2][c] = y_dist_pix
		paramsWv[3][c] = y_disp_pix
		paramsWv[4][c] = z_dist_pix
		paramsWv[5][c] = z_disp_pix
		paramsWv[6][c] = total_disp_pix
		paramsWv[7][c] = total_dist_pix
		paramsWv[8][c] = r_mean_pix	//for this segment
		paramsWv[9][c] = r_stdev_pix
		paramsWv[10][c] = r_min_pix
		paramsWv[11][c] = r_max_pix		
		//store results (microns)		
		paramsWv[numParams+0][c] = x_dist_micron
		paramsWv[numParams+1][c] = x_disp_micron
		paramsWv[numParams+2][c] = y_dist_micron
		paramsWv[numParams+3][c] = y_disp_micron
		paramsWv[numParams+4][c] = z_dist_micron
		paramsWv[numParams+5][c] = z_disp_micron
		paramsWv[numParams+6][c] = total_disp_micron
		paramsWv[numParams+7][c] = total_dist_micron
		paramsWv[numParams+8][c] = r_mean_micron	//for this segment
		paramsWv[numParams+9][c] = r_stdev_micron
		paramsWv[numParams+10][c] = r_min_micron
		paramsWv[numParams+11][c] = r_max_micron
		
		if (i==0)		//during one iteration label rows
		//store results (pixels)
		SetDimLabel 0,0,x_dist_pix,paramsWv
		SetDimLabel 0,1,x_disp_pix,paramsWv
		SetDimLabel 0,2,y_dist_pix,paramsWv
		SetDimLabel 0,3,y_disp_pix,paramsWv
		SetDimLabel 0,4,z_dist_pix,paramsWv
		SetDimLabel 0,5,z_disp_pix,paramsWv
		SetDimLabel 0,6,total_disp_pix,paramsWv
		SetDimLabel 0,7,total_dist_pix,paramsWv
		SetDimLabel 0,8,r_mean_pix,paramsWv	//for this segment
		SetDimLabel 0,9,r_stdev_pix,paramsWv
		SetDimLabel 0,10,r_min_pix,paramsWv
		SetDimLabel 0,11,r_max_pix,paramsWv		
		//store results (microns)		
		SetDimLabel 0,numParams+0,x_dist_micron,paramsWv
		SetDimLabel 0,numParams+1,x_disp_micron,paramsWv
		SetDimLabel 0,numParams+2,y_dist_micron,paramsWv
		SetDimLabel 0,numParams+3,y_disp_micron,paramsWv
		SetDimLabel 0,numParams+4,z_dist_micron,paramsWv
		SetDimLabel 0,numParams+5,z_disp_micron,paramsWv
		SetDimLabel 0,numParams+6,total_disp_micron,paramsWv
		SetDimLabel 0,numParams+7,total_dist_micron,paramsWv
		SetDimLabel 0,numParams+8,r_mean_micron,paramsWv	//for this segment
		SetDimLabel 0,numParams+9,r_stdev_micron,paramsWv
		SetDimLabel 0,numParams+10,r_min_micron,paramsWv
		SetDimLabel 0,numParams+11,r_max_micron,paramsWv		
		endif				
		
		if (calcSegParams)
			paramsWv[][0] += paramsWv[p][c]	//add this to total sum	
		endif
	endfor
	
	note/nocr paramsWv, "indexRef:"+tracingIndexRef+";winSizeIs1XNot2X:"+num2str(winSizeIs1XNot2X)+";segmentList:"+Replacestring(";",segList,",")+";"
	note/nocr paramsWv, "micronsPerPixel_used:"+num2str(micronsPerPixel_used)+";"
	note/nocr paramsWv, "micronsPerZStep:"+num2str(micronsPerZStep)+";numSegs:"+num2str(numSegs)+";numSegsInCalc:"+num2str(numSegsInCalc)+";"
	note/nocr paramsWv, "tracedWaveRef:"+tracedWaveRef+";combinedSegRef:"+tracing_getCombinedSegref(tracedWaveRef)+";"
	note/nocr paramswv, "baseName:"+baseName+";forceBaseName:"+forcebaseName+";"
	
	return paramsOutRef
end


function/S tracing_getParamsHeader()
	String paramsRef = "tracing_paramsHeader"
	
	Variable numParams = 12	//only counting first half, in pixel units. Actual amount is double to include radius units
	
	Make/O/T/N=(numParams*2) $paramsRef
	WAVE/T temp = $paramsRef
	
	temp[0] = "x_dist"
	temp[1] = "x_disp"
	temp[2] = "y_dist"
	temp[3] = "y_disp"
	temp[4] = "z_dist"
	temp[5] = "z_disp"
	temp[6] = "total_disp"
	temp[7] = "total_dist"
	temp[8] = "r_mean"
	temp[9] = "r_stdev"
	temp[10] = "r_min"
	temp[11] = "r_max"
	
	temp[0,numParams] = temp[p] + "_pix"
	temp[numParams,] = temp[p-numParams] + "_micron"
	
	return paramsRef

end


function img_rotate3D(imgWv,rotPlaneNum,outRef)
	WAVE imgWv
	Variable rotPlaneNum
	String outRef
	
	if (rotPlaneNum!=1)		//only straightforward for rotPlaneNum == 1 see below
		return 0
	endif
	
	Variable i, perpDim, lenPerpDim
							//takes xz slices, puts y into z
	perpDim = 1			//reverse is just repeating the same call on the resultant image
							//y is in z, so swap xz again to put z back into z
							
	
	lenPerpDim = dimsize(imgwv,perpDim)	
	for (i=0;i<lenPerpDim;i+=1)
		imagetransform/PTYP=(rotPlaneNum)/P=(i) getplane imgWv
		WAVE M_imagePlane
		if (i==0)
			Duplicate/O M_ImagePlane, $outref/wave=out
		else
			Concatenate/NP=2 {M_imagePlane},out
		endif	
	endfor	
end

//precision appears to be one decimal place short of the swc file :( but it could be much worse!
function img_loadSWC(outRef,numLinesGuess)
	String outRef
	Variable numLinesGuess	//pass this will help it run faster.. can be over or under, over is safer
	
	if (!strlen(outRef))
		outRef = "out"
	endif
		
	Variable txtRefNum
	Open/R/T=".swc" txtRefNum as ""
	if (!txtRefNum)
		return -1
	endif
	

	Variable lineNumber=0, len,firstLine=1
	String buffer
	Variable overGuessBufferSize = 50		//how many more lines to add if over guess? (bigger should reduce overhead at a small cost of wave size)
	
	Variable numParams = 7	//expected format of input:
	//each line except the 1st which is header is:
	//pntNum typeNum xPos yPos zPos radius parentNum[newLine]
	Variable pntNum,typeNum,parentNum
	Double xPos,yPos,zPos,radius
	Make/O/D/N=(numLinesGuess,numParams) $outRef/wave=out
	do
		FReadLine txtRefNum, buffer
		len = strlen(buffer)
		if (firstLine)
			Print "header/line0 text = ",buffer
			firstLine = 0
			continue
		endif
		if (len == 0)
			break		// No more lines to be read
		endif
		//check if over the size guess and redimension by 1 (this is the inefficient part)
		if (lineNumber > (dimsize(out,0) - 1))
			redimension/N=(dimsize(out,0) + overGuessBufferSize,-1) out
		endif
		sscanf buffer, "%i %i %f %f %f %f %i",pntNum,typeNum,xPos,yPos,zPos,radius,parentNum
		out[lineNumber][0] = pntNum
		out[lineNumber][1] = typeNum
		out[lineNumber][2] = xPos
		out[lineNumber][3] = yPos
		out[lineNumber][4] = zPos
		out[lineNumber][5] = radius
		out[lineNumber][6] = parentNum
		
		lineNumber += 1
	while (1)
	
	//resize to actual number of lines read
	Redimension/N=(lineNumber,-1) out
	SetDimLabel 1,0,pntNum,out
	SetDimLabel 1,1,typeNum,out
	SetDimLabel 1,2,xPos,out
	SetDimLabel 1,3,yPos,out
	SetDimLabel 1,4,zPos,out
	SetDimLabel 1,5,radius,out
	SetDimLabel 1,6,parentNum,out

	Close txtRefNum
end

//OVERWRITES INPUT WAVE, considering making a backup of the original first
function img_swcToPixels(swcWv,micronPerPixel_x,micronPerPixel_y,micronPerPixel_z)
	WAVE swcWv
	Double micronPerPixel_x, micronPerPixel_y,micronPerPixel_z
	
	swcWv[][%xPos] /= micronPerPixel_x
	swcWv[][%yPos] /= micronPerPixel_y
	swcWv[][%zPos] /= micronPerPixel_z	
end

//MAY OVERWRITE ANY TRACING ON CURRENT SEGMENT
//tracing window should be top graph
//currently doesn't handle radius scaling. all are set to 10 pnt 10 pixels...
function img_pixelSwcToTracing(pixelSwcWv)
	WAVE pixelSwcWv //expect wave loaded from img_loadSWC and converted to pixel values with img_swcToPixels
	
	SVAR/Z tracing_currTracingWaveName
	if (!Svar_exists(tracing_currTracingWaveName))
		Print "initialize image tracing with tracing_addseg() before calling this function"
	endif
	
	WAVE currTraceWv = $tracing_currTracingWaveName
	//currTraceWv has format xPixLoc yPixLoc xPixNearest yPixNearest zPixLoc radiusPnts radiusPix
	//swc has format pntNum typeNum xPix yPix zPix radius parentNum
	Variable np = dimsize(pixelSwcWv,0)
	Redimension/N=(np,-1) currTraceWv
	currTraceWv[][0] = pixelSwcWv[p][2]		//transfer x values
	currTraceWv[][2] = pixelSwcWv[p][2]	
	currTraceWv[][1] = pixelSwcWv[p][3]
	currTraceWv[][3] = pixelSwcWv[p][3]
	currTraceWv[][4] = pixelSwcWv[p][4]
	currTraceWv[][5,6] = nan//10
	
	tracing_doUpdates(winname(0,1),nan,nan,nan)		//updates the ancillary tracing variables/waves
	tracing_follow("",0,nan,1)							//start off at point 0 (this also seems to be a way to start the radius tracking)
	
end

function tracing_autoRadius_all(winN,maxNumSteps,arcRadius,numArcRadiusSteps,startPnt,num,numTestAngles,updateCenters)
	String winN
	Variable maxNumSteps 	//see tracing_getXYSlope
	Variable arcRadius,numArcRadiusSteps
	Variable startPnt,num,numTestAngles,updateCenters
	
	Variable invert=0
	String autoRadiusThresholdInfo=""//"1;0;"
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	Variable start=numtype(startPnt) ? 0 : startpnt
		
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D ccWv = $combinedSegRef
	
	//reset history wave storing automated radius measurement results
	String autoRadiusAllRef = combinedSegRef + "_rad"
	Variable numRows = dimsize(ccwv,0)
	Variable numInterpParams = 43	//check end of interp function
	Make/O/d/n=(numRows,numInterpParams) $autoRadiusAllRef/wave=results;results=nan
	
	Variable pnts = numtype(num) ? dimsize(ccwv,0) : num,i,pnt		//stopping after first and before last pnt
	for (i=0;i<pnts;i+=1)
		pnt=start+i
		tracing_follow(winN,pnt,nan,1)
		//print "pnt",pnt,"slopeStepSizes",slopeStepSizes,"arcRadius",arcRadius,"numArcRadiusSteps",numArcRadiusSteps,"autoRadiusThresholdInfo",autoRadiusThresholdInfo,"invert",invert
		tracing_autoRadius(pnt,winN,maxNumSteps,arcRadius,numArcRadiusSteps,invert,autoRadiusThresholdInfo,autoRadiusAllRef,numTestAngles,updateCenters)
		doupdate
	endfor
	
	Print "tracing_autoRadius_all_ref:",autoRadiusAllRef
end

function tracing_autoRadius(ccPntNum,winN,maxNumSteps,arcRadius,numArcRadiusSteps,invert,autoRadiusThresholdInfo,resultsRef,numTestAngles,updateCenters)
	Variable ccPntNum; String winN
	Variable maxNumSteps 	//see number of points to average in either direction of current point for determining slope
	Variable arcRadius,numArcRadiusSteps
	String resultsRef
	Variable invert		//was designed for cells brighter inside, dimmer outside. if flipped (as in DIC), pass true for this
	String autoRadiusThresholdInfo
	Variable numTestAngles		//pass >1 to try more test angles and make sure we have the most orthogonal
	Variable updateCenters
	
	if (numtype(ccPntNum))
		ccPntNum = tracing_getSelPntData("Graph0",nan)		//current selection
	endif
	
	Variable origWidth_pix = 100
	Variable xyCropSize_pix = 100
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	setwindow $winN userdata(autoRadiusPerformed) = num2str(1)		//allows other helpful windows to be created by tracing_follow()
	
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D ccWv = $combinedSegRef

	Double x0=ccWv[ccPntNum][0],y0=ccWv[ccPntNum][1],z0=ccWv[ccPntNum][4]
	Double angle = tracing_getXYSlope(ccPntNum,winN,maxNumSteps)
	if (numTestAngles < 2)
		tracing_interp(angle-90,arcRadius,numArcRadiusSteps,invert,autoRadiusThresholdInfo,ccPntNum,winN,"interpTest",resultsRef,0,updateCenters)
	else
		//numTestangles should be even so total is odd to allow main angle to be central
		make/o/d/n=(numTestAngles+1) testAngles,angleResults
		Variable spaceBetweenTests = 180 / (numTestAngles-1)
		testAngles[0]=angle-90
		testAngles[1,]=angle-180+(p-1)*spaceBetweenTests
		//180 degrees of non-redundant space, 90 on each side of angle
		angleResults=tracing_interp(testAngles[p],arcRadius,numArcRadiusSteps,invert,autoRadiusThresholdInfo,ccPntNum,winN,"interpTest",resultsRef,1,updateCenters)
		wavestats/q angleResults
		tracing_interp(testAngles[V_minLoc],arcRadius,numArcRadiusSteps,invert,autoRadiusThresholdInfo,ccPntNum,winN,"interpTest",resultsRef,0,updateCenters)	
		//print "testAngles",testAngles,"angleResults",angleResults
	endif
end


function tracing_getXYSlope(ccPntNum,winN,maxNumSteps)
	Variable ccPntNum; String winN
	Variable maxNumSteps		//how far out to look in estimating points
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D ccWv = $combinedSegRef
	
	Variable xCol=0,yCol=1
	
	Double cc_x=ccwv[ccPntNum][xCol],cc_y=ccwv[ccPntNum][yCol],dx,dy,currMag,currAngle,totalAngle=0,totalMultiplier=0
	Variable i,minInd=0,maxInd=dimsize(ccwv,0)-1,count=0,weight=0
	Variable prevInd,postInd
	Complex currSlope
	for (i=0;i<maxNumSteps;i+=1)
		prevInd = ccPntNum-i-1
		postInd = ccPntNum+i+1
		
		if (prevInd >= minInd)		//only consider points in range
			count+=1
			dx=cc_x-ccwv[prevInd][xCol]
			dy=cc_y-ccwv[prevInd][yCol]
			currSlope=r2polar(cmplx(dx,dy))
			currMag=real(currSlope)
			currAngle=imag(currSlope) * 180 / pi
			totalAngle+=currAngle 
		endif
		
		if (postInd <= maxInd)			//only consider points in range
			count+=1
			dx=ccwv[postInd][xCol]-cc_x
			dy=ccwv[postInd][yCol]-cc_y
			currSlope=r2polar(cmplx(dx,dy))
			currMag=real(currSlope)
			currAngle=imag(currSlope) * 180 / pi
			totalAngle+=currAngle	
		endif
	
	endfor
	
	totalAngle /= count
		
	return totalAngle
end

//never worked perfectly, and now would need updating because tracing_storeZValueForCurrPnt() is no longer used. became obsolete when started indicating
//point cross sections with an oval
function tracing_interp(sectionAngle,arcRadius,numArcRadiusSteps,invert,autoRadiusThresholdInfo,ccPntNum,winN,outRef,resultsRef,noSave,updateCenters)
	Variable ccPntNum; String winN
	Double sectionAngle		//estimated angle of neuron local to this point e.g. from calls to tracing_getXYSlope()
	Variable arcRadius			//number of pixels of length to interpolate on either side of point
	Variable numArcRadiusSteps	//number of steps within that length to take
	String outRef				//interpolated result
	String resultsRef		//optionally pass to store results for this point in an array for all points
	Variable invert		//was designed for cells brighter inside, dimmer outside. if flipped (as in DIC), pass true for this
	String autoRadiusThresholdInfo
	Variable noSave		//pass to get radius estiamte only
	Variable updateCenters		//recenter based on interpolation and width. Ignored if noSave is true
	//ccPnt pass to store line 
	
	Variable saveRawData=1		//set to store orthogonal interpolation (orthoInterp)
	String interpRef=winN+ "ORTHO"
	String interpFitRef=winN+"ORTHOF"
	String interpXVals="winN"+"ORTHOX"
	String interpYVals="winN"+"ORTHOY"
	String interpWidth="winN"+"ORTHOW"
	Variable useThreshold=strlen(autoRadiusThresholdInfo)>0		//use a threshold (held in this variable, cannot be zero)to determine edges instead of fit.. intended for use with ROI tracing to get widths
	
	Variable orthoNum = 5		//number of orthogonal steps to add to average. 1 is an average of 3: main line, one negative and one positive orthogonal line
	Variable padPix = 40//20
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D ccWv = $combinedSegRef
	String segLabel = 	GetDimLabel(ccwv, 0, ccPntNum)
	
	if (!strlen(segLabel))
		Print "tracing_interp(): could not find seg label! aborting"
		return 0
	endif
	
	Variable segNum = tracing_segNumFromSegRef(segLabel)
	Variable segPntNum = tracing_getSegPntFromSegRef(segLabel)
	String segRef = tracing_getSegNameForCCPnt(winN,ccPntNum)
	WAVE segWv= $segRef
	
	Double sectionAngle_rad=sectionAngle*pi/180
	Double m = tan(sectionAngle_rad)
	Double xv = ccWv[ccPntNum][0],dx
	Double yv = ccWv[ccPntNum][1],dy
	Double zv = ccWv[ccPntNum][4]
	
	Double yint = -m*xv + yv
	Variable stepSize = arcRadius / numArcRadiusSteps
	Variable totalNumSteps = 1 + 2*numArcRadiusSteps		//get value at center point and values along radius on either side
	Variable centerPnt=numArcRadiusSteps
	Make/O/D/N=(totalNumSteps) $outRef/wave=out
	Make/o/d/N=(totalNumSteps,2) tracing_interpXYVals
	
	if (m == 0)		//flat line, dx = stepSize
		dx = stepSize
		dy = 0
	elseif (numtype(m) == 1)		//verticle line dy = stepSize, dx = 0
		dx = 0
		dy = stepSize
	else
		dx = stepSize/sqrt(1+m^2)
		dy = stepSize/sqrt(1+(1/m^2)) * ( (m < 0) ? -1 : 1)		//slope information not held in dx,dy calc, add that with by multipying by -1 or 1
	endif
	Double m2 = dy/dx		//sanity check
	tracing_interpXYVals[][0] = xv + (p-numArcRadiusSteps)*dx		//x values
	tracing_interpXYVals[][1] = yv + (p-numArcRadiusSteps)*dy		//y values
	
	//print/d "origAngle",sectionAngle+90,"sectionAngle",sectionAngle,"ccPntNum",ccPntNum,"xv",xv,"dx",dx,"yv",yv,"dy",dy,"m",m,"m2",m2,"yint",yint
	
	imagetransform/PTYP=0/P=(zv) getplane $tracedWaveName
	WAVE/D M_imagePlane
	Redimension/N=(-1,-1) M_ImagePlane
	img_cropToCenter(xv,yv,2*arcRadius+padPix,M_ImagePlane,"tracing_interpTemp")
	ImageInterpolate/U=8/Dest=tracing_interpTemp2 bilinear $"tracing_interpTemp"
	try
		out = tracing_interpTemp2(xv + (p-numArcRadiusSteps)*dx)(yv + (p-numArcRadiusSteps)*dy)	
	catch 
		print "tracing_interp() on ccpnt",ccPntNum,"error on tracing_interpTemp2 ignored,err",GetRTError(1)
	endtry
	Variable averageCount = 1
	
	//take average across orthogonal slices
	Variable i,orthoMult
	for (i=0;i<orthoNum;i+=1)
		orthoMult = i+1
		out += tracing_interpTemp2(xv-dx*orthoMult + (p-numArcRadiusSteps)*dx)(yv+dy*orthoMult + (p-numArcRadiusSteps)*dy)
		orthoMult *= -1		//to get other direction
		out += tracing_interpTemp2(xv-dx*orthoMult + (p-numArcRadiusSteps)*dx)(yv+dy*orthoMult + (p-numArcRadiusSteps)*dy)
		averageCount += 2
	endfor
	out /= averageCount
	
	//get axis scaling right (depends on #numArcRadiusSteps)
	setscale/P x,0,stepSize,"p",out
	duplicate/o out,radiusDisp
	
	Variable bkgProp=nan,bkgLen_P=nan,noRiseCross=nan,noFallCross=nan,inLevel=nan,outLevel=nan
	Double leftBkg=nan,rightBkg=nan,bkg=nan,risePos=nan,risePos1=nan,fallPos=nan,width=nan,centerCalc=nan,fallPos1=nan,centerCalc1=nan,normFactor=nan
	Double tauFromfit=nan,riseFromFit=nan,fallFromFit=nan,widthFromfit=nan,centerFromFit=nan,interpStart=nan,interpEnd=nan
	Double rise_p1,fall_p1,width_p1,center_p1,rise_p5,fall_p5,width_p5,center_p5,rise_p9,fall_p9,width_p9,center_p9,fitMaskThreshold
	Double gauss_y0,gauss_A,gauss_x0,gauss_width,K0,gauss_fwhm=nan,gauss_fwtm=nan
	if (useThreshold)	//SEE WHEN LINE CROSSES THRESHOLD -- assumes center is ABOVE threshold
		inLevel=str2num(stringfromlist(0,autoRadiusThresholdInfo))
		outLevel=str2num(stringfromlist(1,autoRadiusThresholdInfo))
		noRiseCross=1;noFallCross=1
		for (i=centerPnt;i>=0;i-=1)
			if (out[i] == outLevel)
				risePos=pnt2x(out,i)
				noRiseCross=0
				break
			endif		
		endfor
		for (i=centerPnt;i<totalNumSteps;i+=1)
			if (out[i] == outLevel)
				fallPos=pnt2x(out,i)
				noFallCross=0
				break
			endif		
		endfor		
		width = fallPos-risePos
		centerCalc = risePos + width/2
		if (noRiseCross || noFallCross)
			Print "noRiseCross",noRiseCross,"noFallCross",noFallCross,"risePos",risePos,"fallPos",fallPos,"width",width,"centerCalc",centerCalc
		endif
		
		if (noSave)
			return width
		endif
	else		//FIT TO LINE SCAN
	
		//subtract background (bkg) from average --added after original version, so not stored as parameter. probably should be...
		bkgProp = 0.05		//percent before AND after image to use in baseline sub
		bkgLen_P = floor(totalNumSteps * bkgProp)
		leftBkg = mean(out,0,bkgLen_P-1)		//x and pnt nums are equal
		rightBkg = mean(out,totalNumSteps-1-bkgLen_P,totalNumSteps-1)
		bkg = (leftBkg + rightBkg)/2
		out -= bkg
		setscale/P x, -arcRadius,stepsize,out
		
		if (invert)
			out*=-1
		endif
		
		Smooth 4, out
		
		WaveStats/Z/Q/P out
		
		//find the rising and falling peak --assumes perfect baseline subtraction so start and end level is 0
		if (V_maxLoc != 0)		//need to watch out for bad angles where orthogonal line is straight along cell
			edgestats/Q/r=[0,V_maxloc]/L=(0,V_max*0.98)/T=10 out
			rise_p1 = V_EdgeLoc1
			rise_p5 = V_EdgeLoc2
			rise_p9 = V_EdgeLoc3
		else
			rise_p1 = 0
			rise_p5 = 0
			rise_p9 = 0
		endif
		if (V_maxLoc < totalNumSteps-1)
			edgestats/Q/r=[V_maxloc,totalNumSteps-1]/L=(V_max*0.98,0)/T=10 out
			fall_p1 = V_EdgeLoc1
			fall_p5 = V_EdgeLoc2
			fall_p9 = V_EdgeLoc3
		else
			fall_p1 = totalNumSteps-1
			fall_p5 = fall_p1
			fall_p9 = fall_p1
		endif
		width_p1 = fall_p1 - rise_p1
		width_p5 = fall_p5 - rise_p5
		width_p9 = fall_p9 - rise_p9		
		center_p1 = rise_p1 + width_p1/2
		center_p5 = rise_p5 + width_p5/2
		center_p9 = rise_p9 + width_p9/2			
		
		//fit to gaussian, masking any saturation
		fitMaskThreshold = V_max * 0.98
		duplicate/o out,tracing_interp_fitMask
		tracing_interp_fitMask=out[p] > fitMaskThreshold ? nan : 1
		k0=0
		curvefit/N=1/Q/W=2/H="1000" gauss out/M=tracing_interp_fitMask
		WAVE/D w_Coef
		gauss_y0=W_coef[0]
		gauss_A=W_coef[1]
		gauss_x0=W_coef[2]
		gauss_width=W_coef[3]
		gauss_fwhm=gauss_width*2*sqrt(2*ln(2))		//full width half max
		gauss_fwtm=gauss_width*2*sqrt(2*ln(10))	//full with at one tenth of max
		centerCalc=gauss_x0
		interpStart=centerCalc-gauss_width/2
		interpEnd=interpStart+gauss_width
		if (noSave)
			return gauss_width
		endif
		
		duplicate/o out,interptestfit,interpWidthDisp
		interptestfit=	gauss_y0+gauss_A*exp(-((x-gauss_x0)/gauss_width)^2)		//W_coef[0]+W_coef[1]*exp(-((x-W_coef[2])/W_coef[3])^2)
		interpWidthDisp=	(x >= interpStart) && (x <= interpEnd) ? 1 : 0
	endif
	
	Double center_dx,center_dy,new_x,new_y
	if (numtype(m))		//m inf, so vertical
		center_dx=0
		center_dy=centerCalc
	elseif (m==0)			//horizontal
		center_dx=centerCalc
		center_dy=0
	else
		center_dx=centerCalc*cos(sectionAngle_rad)
		center_dy=centerCalc*sin(sectionAngle_rad)
	endif
	
	new_x = xv+center_dx
	new_y = yv+center_dy
	
	if (updateCenters)
		WAVE segWv= $segRef
		segWv[segPntNum][0]=new_x
		segWv[segPntNum][1]=new_y
		print "oldx",xv,"newx",new_x,"oldy",yv,"newy",new_y
	endif
	
	//currently using wit from edgestats, skipping the fit: uncomment other version to use fit stats
	//this function stopped working when starting using oval for indicating point cross section. would need to fix
	//tracing_storeZValueForCurrPnt(winN,setToPixelVal=gauss_width/2,setDisplay=1)
	//tracing_storeZValueForCurrPnt(winN,setToPixelVal=widthFromfit,setDisplay=1)
	
	tracing_doUpdates(winN,nan,nan,nan)
	//Print "m",m,"m2",m2,risePos",risePos, "fallPos",fallPos, "width",width,"centerCalc","tauFromfit",tauFromfit,"riseFromFit",riseFromFit,"fallFromFit",fallFromFit,"widthFromfit",widthFromfit
	
	if (saveRawData)
		WAVE/Z interpSave = $interpRef
		Variable cols=dimsize(ccWv,0)
		Variable rows=dimsize(out,0)
		
		//handle interpolation saving
		if (!WaveExists(interpSave) || (rows != dimsize(interpSave,0)) || (cols != dimsize(interpSave,1)) || (segPntNum==0))
			Duplicate/o out,$interpRef/wave=interpSave
			Duplicate/o out,$interpFitRef/wave=interpFitSave
			duplicate/o out,$interpXVals/wave=interpX
			duplicate/o out,$interpYVals/wave=interpY
			duplicate/o out,$interpWidth/wave=interpW
			redimension/n=(-1,cols) interpSave,interpFitSave,interpX,interpY,interpW
			interpSave=nan;interpFitSave=nan;interpX=nan;interpY=nan;interpW=nan;
		else
			wave interpFitSave = $interpFitRef
			wave interpX = $interpXVals
			wave interpY = $interpYVals
			wave interpW = $interpWidth
		endif	
		interpSave[][ccPntNum] = out[p]
		interpFitSave[][ccPntNum] = interptestfit[p]
		interpX[][ccPntNum] = tracing_interpXYVals[p][0]
		interpY[][ccPntNum] = tracing_interpXYVals[p][1]
		interpW[][ccPntNum] = interpWidthDisp[p]
	endif
	
	if (strlen(resultsRef) && WAveExists($resultsRef))
		Variable paramsStart = 0
		wave/d results = $resultsRef
		Variable c=0;results[ccPntNum][paramsStart+c]=sectionAngle
		c+=1;results[ccPntNum][paramsStart+c]=numArcRadiusSteps
		c+=1;results[ccPntNum][paramsStart+c]=m
		c+=1;results[ccPntNum][paramsStart+c]=xv
		c+=1;results[ccPntNum][paramsStart+c]=yv
		
		c+=1;results[ccPntNum][paramsStart+c]=zv
		c+=1;results[ccPntNum][paramsStart+c]=yint
		c+=1;results[ccPntNum][paramsStart+c]=stepSize
		c+=1;results[ccPntNum][paramsStart+c]=totalNumSteps
		c+=1;results[ccPntNum][paramsStart+c]=dx
		
		c+=1;results[ccPntNum][paramsStart+c]=dy
		c+=1;results[ccPntNum][paramsStart+c]=orthoNum
		c+=1;results[ccPntNum][paramsStart+c]=padPix
		c+=1;results[ccPntNum][paramsStart+c]=averageCount
		c+=1;results[ccPntNum][paramsStart+c]=rise_p1
		
		c+=1;results[ccPntNum][paramsStart+c]=fall_p1
		c+=1;results[ccPntNum][paramsStart+c]=width_p1
		c+=1;results[ccPntNum][paramsStart+c]=center_p1	
		c+=1;results[ccPntNum][paramsStart+c]=rise_p5
		c+=1;results[ccPntNum][paramsStart+c]=fall_p5
		
		c+=1;results[ccPntNum][paramsStart+c]=width_p5
		c+=1;results[ccPntNum][paramsStart+c]=center_p5	
		c+=1;results[ccPntNum][paramsStart+c]=rise_p9
		c+=1;results[ccPntNum][paramsStart+c]=fall_p9
		c+=1;results[ccPntNum][paramsStart+c]=width_p9
		
		c+=1;results[ccPntNum][paramsStart+c]=center_p9		
		c+=1;results[ccPntNum][paramsStart+c]=fitMaskThreshold
		c+=1;results[ccPntNum][paramsStart+c]=gauss_y0
		c+=1;results[ccPntNum][paramsStart+c]=gauss_A		
		c+=1;results[ccPntNum][paramsStart+c]=gauss_x0
		
		c+=1;results[ccPntNum][paramsStart+c]=gauss_width	 
		c+=1;results[ccPntNum][paramsStart+c]=gauss_width/2		
		c+=1;results[ccPntNum][paramsStart+c]=centerCalc		
		c+=1;results[ccPntNum][paramsStart+c]=center_dx
		c+=1;results[ccPntNum][paramsStart+c]=center_dy
		
		c+=1;results[ccPntNum][paramsStart+c]=new_x
		c+=1;results[ccPntNum][paramsStart+c]=new_y 
		c+=1;results[ccPntNum][paramsStart+c]=interpStart 
		c+=1;results[ccPntNum][paramsStart+c]=interpEnd 
		c+=1;results[ccPntNum][paramsStart+c]=gauss_fwhm 
		
		c+=1;results[ccPntNum][paramsStart+c]=gauss_fwhm/2 
		c+=1;results[ccPntNum][paramsStart+c]=gauss_fwtm 
		c+=1;results[ccPntNum][paramsStart+c]=gauss_fwtm/2 //43
				
		setdimlabel 0, ccPntNum,$GetDimLabel(ccwv, 0, ccPntNum ),results
		if (ccPntNum==0)
			c=0;SetDimLabel 1,paramsStart+c,sectionAngle,results
			c+=1;SetDimLabel 1,paramsStart+c,numArcRadiusSteps,results
			c+=1;SetDimLabel 1,paramsStart+c,m,results
			c+=1;SetDimLabel 1,paramsStart+c,xv,results
			c+=1;SetDimLabel 1,paramsStart+c,yv,results
			
			c+=1;SetDimLabel 1,paramsStart+c,zv,results
			c+=1;SetDimLabel 1,paramsStart+c,yint,results
			c+=1;SetDimLabel 1,paramsStart+c,stepSize,results
			c+=1;SetDimLabel 1,paramsStart+c,totalNumSteps,results
			c+=1;SetDimLabel 1,paramsStart+c,dx,results
			
			c+=1;SetDimLabel 1,paramsStart+c,dy,results
			c+=1;SetDimLabel 1,paramsStart+c,orthoNum,results
			c+=1;SetDimLabel 1,paramsStart+c,padPix,results
			c+=1;SetDimLabel 1,paramsStart+c,averageCount,results
			c+=1;SetDimLabel 1,paramsStart+c,rise_p1,results
			
			c+=1;SetDimLabel 1,paramsStart+c,fall_p1,results
			c+=1;SetDimLabel 1,paramsStart+c,width_p1,results
			c+=1;SetDimLabel 1,paramsStart+c,center_p1	,results
			c+=1;SetDimLabel 1,paramsStart+c,rise_p5,results
			c+=1;SetDimLabel 1,paramsStart+c,fall_p5,results
			
			c+=1;SetDimLabel 1,paramsStart+c,width_p5,results
			c+=1;SetDimLabel 1,paramsStart+c,center_p5	,results
			c+=1;SetDimLabel 1,paramsStart+c,rise_p9,results
			c+=1;SetDimLabel 1,paramsStart+c,fall_p9,results
			c+=1;SetDimLabel 1,paramsStart+c,width_p9,results
			
			c+=1;SetDimLabel 1,paramsStart+c,center_p9	,results	
			c+=1;SetDimLabel 1,paramsStart+c,fitMaskThreshold,results
			c+=1;SetDimLabel 1,paramsStart+c,gauss_y0,results
			c+=1;SetDimLabel 1,paramsStart+c,gauss_A	,results	
			c+=1;SetDimLabel 1,paramsStart+c,gauss_x0,results
			
			c+=1;SetDimLabel 1,paramsStart+c,gauss_width	 ,results
			c+=1;SetDimLabel 1,paramsStart+c,gauss_radius,results
			c+=1;SetDimLabel 1,paramsStart+c,centerCalc,results
			c+=1;SetDimLabel 1,paramsStart+c,center_dx,results
			c+=1;SetDimLabel 1,paramsStart+c,center_dy,results
			
			c+=1;SetDimLabel 1,paramsStart+c,new_x,results
			c+=1;SetDimLabel 1,paramsStart+c,new_y,results
			c+=1;SetDimLabel 1,paramsStart+c,interpStart,results
			c+=1;SetDimLabel 1,paramsStart+c,interpEnd,results
			c+=1;SetDimLabel 1,paramsStart+c,gauss_fwhm,results
			
			c+=1;SetDimLabel 1,paramsStart+c,gauss_fwhm_radius,results
			c+=1;SetDimLabel 1,paramsStart+c,gauss_fwtm,results
			c+=1;SetDimLabel 1,paramsStart+c,gauss_fwtm_radius,results
		endif
	endif

	if (invert) //swap back now
	//	out*=-1
	//	interptestfit*=-1
	endif
	
	WAVE/Z interp_disp
	if (!waveexists(interp_disp))
		make/o/n=(2,2) interp_disp
	endif
	
	interp_disp[][1] = 0.5		//y values 0.5 sets height on graph
	interp_disp[0][0] = risePos
	interp_disp[1][0] = fallPos
	
end


//may have once sort of worked but never perfectly. now definitely broken because tracing_storeZValueForCurrPnt is obsolete since started drawing cross section as oval
function tracing_interpz(sectionAngle,arcRadius,numArcRadiusSteps,ccPntNum,winN,outRef)
	Variable ccPntNum; String winN
	Double sectionAngle		//estimated angle of neuron local to this point e.g. from calls to tracing_getXYSlope()
	Variable arcRadius			//number of pixels of length to interpolate on either side of point
	Variable numArcRadiusSteps	//number of steps within that length to take
	String outRef				//interpolated result
	
	Variable orthoNum = 0		//number of orthogonal steps to add to average. 1 is an average of 3: main line, one negative and one positive orthogonal line
	Variable padPix = 20
	Variable initZRadius = 10
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D ccWv = $combinedSegRef
	String segLabel = 	GetDimLabel(ccwv, 0, ccPntNum)
	
	if (!strlen(segLabel))
		Print "tracing_interp(): could not find seg label! aborting"
		return 0
	endif
	
	Variable segNum = tracing_segNumFromSegRef(segLabel)
	Variable segPntNum = tracing_getSegPntFromSegRef(segLabel)
	String segRef = tracing_getSegNameForCCPnt(winN,ccPntNum)
	WAVE segWv= $segRef
	
	Double m = tan(sectionAngle*pi/180)
	Double xv = ccWv[ccPntNum][0],dx
	Double yv = ccWv[ccPntNum][1],dy
	Double zv = ccWv[ccPntNum][4]
	
	Double yint = -m*xv + yv
	Variable stepSize = arcRadius / numArcRadiusSteps
	Variable totalNumSteps = 1 + 2*numArcRadiusSteps		//get value at center point and values along radius on either side
	Make/O/D/N=(totalNumSteps) $outRef/wave=out
	Make/o/d/N=(totalNumSteps,2) tracing_interpXYVals
	
	if (m == 0)		//flat line, dx = stepSize
		dx = stepSize
		dy = 0
	elseif (numtype(m) == 1)		//verticle line dy = stepSize, dx = 0
		dx = 0
		dy = stepSize
	else
		dx = stepSize/sqrt(1+m^2)
		dy = stepSize/sqrt(1+(1/m^2)) * ( (m < 0) ? -1 : 1)		//slope information not held in dx,dy calc, add that with by multipying by -1 or 1
	endif
	Double m2 = dy/dx

	tracing_interpXYVals[][0] = xv + (p-numArcRadiusSteps)*dx		//x values
	tracing_interpXYVals[][1] = yv + (p-numArcRadiusSteps)*dy		//y values
	
	imagetransform/PTYP=0/P=(zv) getplane $tracedWaveName
	WAVE/D M_imagePlane
	Redimension/N=(-1,-1) M_ImagePlane
	img_cropToCenter(xv,yv,2*arcRadius+padPix,M_ImagePlane,"tracing_interpTemp")
	ImageInterpolate/U=8/Dest=tracing_interpTemp2 bilinear $"tracing_interpTemp"
	out = tracing_interpTemp2(xv + (p-numArcRadiusSteps)*dx)(yv + (p-numArcRadiusSteps)*dy)	
	Variable averageCount = 1
	
	Variable i,orthoMult
	for (i=0;i<orthoNum;i+=1)
		orthoMult = i+1
		out += tracing_interpTemp2(xv-dx*orthoMult + (p-numArcRadiusSteps)*dx)(yv+dy*orthoMult + (p-numArcRadiusSteps)*dy)
		orthoMult *= -1		//to get other direction
		out += tracing_interpTemp2(xv-dx*orthoMult + (p-numArcRadiusSteps)*dx)(yv+dy*orthoMult + (p-numArcRadiusSteps)*dy)
		averageCount += 2
	endfor
	out /= averageCount
	setscale/P x, -arcRadius,stepsize,out
	WaveStats/Z/Q/P out
	
	edgestats/Q/r=[0,V_maxloc]/L=(V_max*0.05,V_max*0.95)/F=0.25/T=10 out
	Double risePos = V_EdgeLoc1
	edgestats/Q/r=[V_maxloc,totalNumSteps-1]/L=(V_max*0.95,V_max*0.05)/T=10 out
	Double fallPos = V_EdgeLoc3	
	Double centerCalc = risePos + (fallPos - risePos)/2
	Double width = fallPos - risePos
	
	Double normFactor = 0.95*V_max
	out /= normFactor
	Make/O/D/N=(3) tracing_interpfitCoefs
	tracing_interpfitCoefs[0] = 2.3		//got this in an initial test run
	tracing_interpfitCoefs[1] = risePos
	tracing_interpfitCoefs[2] = fallPos
	
	FuncFit/N=1/Q/W=2 fit_simpleSigmoids,tracing_interpfitCoefs,out
	Double tauFromfit = tracing_interpfitCoefs[0]
	Double riseFromFit = min(tracing_interpfitCoefs[1],tracing_interpfitCoefs[2])
	Double fallFromFit = max(tracing_interpfitCoefs[1],tracing_interpfitCoefs[2])
	Double widthFromfit = fallFromfit-riseFromFit
	Duplicate/o out, interptestfit
	interptestfit = fit_simpleSigmoids(tracing_interpfitCoefs,x)
	
	//tracing_storeZValueForCurrPnt(winN,setToPixelVal=widthFromfit,setDisplay=1)
	
	tracing_doUpdates(winN,nan,nan,nan)
	//Print "risePos",risePos, "fallPos",fallPos, "width",width,"centerCalc","tauFromfit",tauFromfit,"riseFromFit",riseFromFit,"fallFromFit",fallFromFit,"widthFromfit",widthFromfit
end

function img_cropToCenter(xCenter,yCenter,size,inWv,outRef)
	Variable xCenter,yCenter,size		//all in pixels, e.g., rows/cols
	WAVE inWv
	String outRef
	
	if (mod(size,2) != 0)
		size+=1		//force evenness, so that same number of rows/cols in either direction from center
	endif
	
	Variable sizeOnSide = size/2
	variable xStart = xCenter-sizeOnSide
	Variable xEnd = xCenter+size		//note that e.g. duplicate/r=[xStart,xStart+size] will actually center the xValue by including one more point that size
	Variable yStart = yCenter-sizeOnSide
	Variable yEnd = yCenter+size
	
		//NEWNEWNEWNEW
//	xStart=max(xStart,dimsize(inwv,0))
//	xEnd=min(xEnd,dimsize(inwv,0))
//	yStart=max(yStart,dimsize(inwv,1))
//	yEnd=min(yEnd,dimsize(inwv,1))
	
	Duplicate/O/R=[xStart,xEnd][yStart,yEnd] inWv, $outRef
		
end

function img_maskAroundCenter(xCenter,yCenter,maskFullLen_pix,maskForParticleNotThreshold,inWv,outRef)
	Variable xCenter,yCenter,maskFullLen_pix		//all in pixels, e.g., rows/cols
	WAVE inWv
	String outRef
	VAriable maskForParticleNotThreshold	//pass to specify type of output
			//if 0 (for threshold) type is /b/u and outside ROI == 0, in ROI == 1
			//if 1 (for imageanalyzeparticles) type is still /b/u but outside ROI = 1 and in = 0
			
	
	if (mod(maskFullLen_pix,2) != 0)
		maskFullLen_pix+=1		//force evenness, so that same number of rows/cols in either direction from center
	endif
	
	Variable sizeOnSide = maskFullLen_pix/2
	variable xStart = xCenter-sizeOnSide
	Variable xEnd = xCenter+sizeOnSide		//note that e.g. duplicate/r=[xStart,xStart+size] will actually center the xValue by including one more point that size
	Variable yStart = yCenter-sizeOnSide
	Variable yEnd = yCenter+sizeOnSide
	
	Variable valAtUnmaskedPixels, valAtMaskedPixels
	Variable dim0 = dimsize(inWv,0)
	Variable dim1 = dimsize(inWv,1)
	make/o/b/u/n=(dim0,dim1) $outref/wave=out
	if (maskForParticleNotThreshold)
		valAtUnmaskedPixels = 0
		valAtMaskedPixels = 1
	else
		valAtUnmaskedPixels = 0
		valAtMaskedPixels = 1	
	endif
	
	out = (p < xStart) || (p > xEnd) || (y < yStart) || (y > yEnd) ? valAtMaskedPixels : valAtUnmaskedPixels
end

function ellipse_momentsToCoords(points,outRef_params,outRef_ellipse,inclParamDimLabels)
	Variable points	//number of points 
	String outRef_params,outRef_ellipse		//pass "" to skip either one. params still calculated but not saved if the former is ""
	Variable inclParamDimLabels		//pass to include param dim labels
	
	Variable particleNum = 0
	
	if (numtype(points) != 0)
		points = 400		//default plot size
	endif
	
	WAVE M_Moments		//from imageanalyzeparticles
	
	Double xCenter = M_moments[particleNum][0]
	Double yCenter = M_moments[particleNum][1]
	Double majorAxisRadius = M_moments[particleNum][2]
	Double minorAxisRadius = M_moments[particleNum][3]
	Double angle_rad = M_moments[particleNum][4]
	
	Print "xCenter",xCenter,"yCenter",yCenter,"majorAxisRadius",majorAxisRadius,"minorAxisRadius",minorAxisRadius,"angle_rad",angle_rad

	return elipse_coords(xCenter,yCenter,majorAxisRadius,minorAxisRadius,angle_rad,points,outRef_params,outRef_ellipse,inclParamDimLabels)
end

//the X-center of the ellipse, the Y-center of the ellipse, the major axis, the minor axis, 
//and the angle (radians) that the major axis makes with the X-direction.
function elipse_coords(xCenter,yCenter,majorAxisRadius,minorAxisRadius,angle_rad,points,outRef_params,outRef_ellipse,inclParamDimLabels)
	Double xCenter,yCenter,majorAxisRadius,minorAxisRadius,angle_rad,points
	String outRef_params,outRef_ellipse		//pass "" to skip either one. params still calculated but not saved if the former is ""
	Variable inclParamDimLabels		//pass to include param dim labels
		
	Double majorAxis_p0x = xCenter - majorAxisRadius*cos(angle_rad-pi)		//not sure why but x needs a mirror image flip to overlay
	Double majorAxis_p1x = xCenter + majorAxisRadius*cos(angle_rad-pi)
	Double majorAxis_p0y = yCenter - majorAxisRadius*sin(angle_rad)
	Double majorAxis_p1y = yCenter + majorAxisRadius*sin(angle_rad)
	
	Double minorAxis_p0x = xCenter - minorAxisRadius*cos(angle_rad-pi)
	Double minorAxis_p1x = xCenter + minorAxisRadius*cos(angle_rad-pi)
	Double minorAxis_p0y = yCenter - minorAxisRadius*sin(angle_rad)
	Double minorAxis_p1y = yCenter + minorAxisRadius*sin(angle_rad)
	
	Double w = atan2(majorAxis_p1y-majorAxis_p0y,majorAxis_p1x-majorAxis_p0x);	
	
	if (strlen(outRef_params))
		Variable numParams = 6 + 9 + 1		//input params + ellipse calculation params + derived params
		make/o/d/n=(numParams) $outRef_params/wave=outp
		outp[0] =  xCenter
		outp[1] =  yCenter
		outp[2] =  majorAxisRadius
		outp[3] =  minorAxisRadius
		outp[4] =  angle_rad
		outp[5] =  points	
		outp[6] =  majorAxis_p0x
		outp[7] =  majorAxis_p1x
		outp[8] =  majorAxis_p0y
		outp[9] =  majorAxis_p1y
		outp[10] =  minorAxis_p0x
		outp[11] =  minorAxis_p1x
		outp[12] =  minorAxis_p0y
		outp[13] =  minorAxis_p1y
		outp[14] =  w
		outp[15] =  majorAxisRadius/minorAxisRadius	//how much larger was major than minor axis?
		if (inclParamDimLabels)
			SetDimLabel 0,0,xCenter,outp
			SetDimLabel 0,1,yCenter,outp
			SetDimLabel 0,2,majorAxisRadius,outp
			SetDimLabel 0,3,minorAxisRadius,outp
			SetDimLabel 0,4,angle_rad,outp
			SetDimLabel 0,5,points	,outp
			SetDimLabel 0,6,majorAxis_p0x,outp
			SetDimLabel 0,7,majorAxis_p1x,outp
			SetDimLabel 0,8,majorAxis_p0y,outp
			SetDimLabel 0,9,majorAxis_p1y,outp
			SetDimLabel 0,10,minorAxis_p0x,outp
			SetDimLabel 0,11,minorAxis_p1x,outp
			SetDimLabel 0,12,minorAxis_p0y,outp
			SetDimLabel 0,13,minorAxis_p1y,outp
			SetDimLabel 0,14,w,outp
			SetDimLabel 0,15,ratio_MajorToMinorRad,outp	//how much larger was major than minor axis?				
		endif
	endif
	
	if (strlen(outRef_ellipse))
		ellipse_plot(points,majorAxisRadius,minorAxisRadius,w,majorAxis_p0x,majorAxis_p1x,majorAxis_p0y,majorAxis_p1y,outRef_ellipse)
	endif
		
	//Print "majorAxis_p0x",majorAxis_p0x,"majorAxis_p1x",majorAxis_p1x,"majorAxis_p0y",majorAxis_p0y,"majorAxis_p1y",majorAxis_p1y
	return minorAxisRadius*2
end

function ellipse_plot(points,majorAxisRadius,minorAxisRadius,w,majorAxis_p0x,majorAxis_p1x,majorAxis_p0y,majorAxis_p1y,outRef)
	Variable points //number of points calculated (density/resolution)
	String outRef		//place to store
	Double majorAxisRadius	//rest are as in elipse_coords
	Double minorAxisRadius
	Double w
	Double majorAxis_p0x
	Double majorAxis_p1x
	Double majorAxis_p0y
	Double majorAxis_p1y
	
	if (!strlen(outRef))
		return 0
	endif
	
	Variable usedPnts
	if (!numtype(points))		//passed has precedence
		usedPnts = points
	else
		usedPnts = 50		//default #
	endif	

	make/o/d/n=(usedPnts)/Free arrx,arry
	Make/O/D/N=(usedPnts,2) $outRef/wave=out
	arrx=majorAxisRadius*cos(p*2*pi/usedPnts);
	arry=minorAxisRadius*sin(p*2*pi/usedPnts);
	out[][0] = (majorAxis_p0x+majorAxis_p1x)/2 + arrx[p]*cos(w) - arry[p]*sin(w)		//x values
	out[][1] = (majorAxis_p0y+majorAxis_p1y)/2 + arrx[p]*sin(w) + arry[p]*cos(w)		//y values
	setdimlabel 1,0,xPos,out
	setdimlabel 1,1,yPos,out
end

function tracing_fitAllSecs(winN)
	String winN
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	Variable i	
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D combinedSegWv = $combinedSegRef
	
	Variable numPoints = dimsize(combinedSegWv,0)
	for (i=0;i<numPoints;i+=1)
		tracing_fitSec(winN,i)
	endfor

end

//calls tracing_fitEllipse which fits an ellipse at the current z plane
//redimensions the segment params wave and stores ellipse parameters
//without changing original parameters
//stores results from  tracing_fitEllipse and its sub-functions
function tracing_fitSec(winN,ccPntNum)
	String winN
	Variable ccPntNum 	//pnt num in [img_name]_cc wave
	
	Variable tracing_plotEllipses = 1	//1 to plot, 0 to hide
	Variable maskFullLen_pix = 100		//WARNING MAY BE DRAMATICALLY EFFECTED BY PIXEL DENSITY
	Variable inclParamDimLabels = 0		//see ellipse_momentsToCoords
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	//get its center loc
	//extract its z plane based on zLoc
	//mask around region based on center loc and maskWidthHeight_pix
	//threshold based on...
	//fit ellipse
	//store fit info after resizing segment data refs
	//set radius to small ellipse radius
	
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D combinedSegWv = $combinedSegRef
	
	String segLabel = 	GetDimLabel(combinedSegWv, 0, ccPntNum)
	
	if (!strlen(segLabel))
		return 0
	endif
	
	Variable segNum = tracing_segNumFromSegRef(segLabel)
	Variable segPntNum = tracing_getSegPntFromSegRef(segLabel)
	String segRef = tracing_getSegNameForCCPnt(winN,ccPntNum)

	Variable origParams = 7		//number of parameters included before adding ellipse analysis
	Wave/D segWv = $segRef
	Variable likelyIncorrectDims = dimsize(segWv,1) <= origParams
	inclParamDimLabels = max(inclParamDimLabels,likelyIncorrectDims)		//if either is 1, will set inclParamDimLabels to 1 
	Variable origCenterPixX = 	segWv[segPntNum][0]	//anything with "orig" is potential changed below and so the original is stored
	Variable origCenterPixY = 	segWv[segPntNum][1]
	Variable origNearestPixX = segWv[segPntNum][2]	
	Variable origNearestPixY = segWv[segPntNum][3]	
	Variable origRadiusPnts = segWv[segPntNum][5]
	Variable origRadiusPix = segWv[segPntNum][6]
	Variable zPixLoc = segWv[segPntNum][4]
	
	//grab the image at the z plane
	imagetransform/PTYP=0/P=(zPixLoc) getplane $tracedWaveName
	WAVE M_imagePlane
	Redimension/N=(-1,-1) M_imagePlane	//appears to have a third dimension of length 1 instead of 0 from imagetransform
	
	String outRef_params = "tracing_ellipseParamsTemp"
	
	tracing_fitEllipse(M_imagePlane,origCenterPixX,origCenterPixY,maskFullLen_pix,inclParamDimLabels,outRef_params,"ellipseFitTest")
	WAVE/D ellipseParams = $outRef_params
	
	Variable numEllipsePArams = dimsize($outRef_params,0)		//expect 7 for origParams and 16 for numEllipseParams. If changes, update tracing_numParamCols
	Variable numColsNeeded = origParams + numEllipsePArams
	Variable needsRedimension = dimsize(segWv,1) < numColsNeeded
	if (needsRedimension)
		redimension/N=(-1,numColsNeeded) segWv
		//segWv[segPntNum][origParams,2*origParams-1] = segWv[p][q-origParams]		//save all original parameters
	endif
	Variable ellipseParamsStart = 2*origParams
	segWv[segPntNum][origParams,*] = ellipseParams[q-origParams]
end

//takes in a 2d wave and fits an ellipse. if centerX,center, and maskFullLen_pix are specified, then fits in the subregion they describe
function tracing_fitEllipse(imgWv,centerPixX,centerPixY,maskFullLen_pix,inclParamDimLabels,outRef_params,outRef_ellipse)
	WAVE imgWv
	Double centerPixX,centerPixY,maskFullLen_pix
	String outRef_params,outRef_ellipse
	Variable inclParamDimLabels	//see ellipse_momentsToCoords
	
	Variable minArea = pi*4^2			//
		
	NVAR/Z tracing_plotEllipses
	if (!NVAR_exists(tracing_plotEllipses))
		Variable/G tracing_plotEllipses = 1 //default for now is to plot ellipses
	endif
	
	//mask for thresholding
	Variable maskForParticleNotThreshold = 0
	img_maskAroundCenter(centerPixX,centerPixY,maskFullLen_pix,maskForParticleNotThreshold,imgWv,"tracing_fitEllipseTemp0")
	imagethreshold/R=$"tracing_fitEllipseTemp0"/M=1/I/Q imgWv
	WAVE M_imageThresh
	maskForParticleNotThreshold = 1
	img_maskAroundCenter(centerPixX,centerPixY,maskFullLen_pix,maskForParticleNotThreshold,M_ImageThresh,"tracing_fitEllipseTemp")
	imageanalyzeparticles/E/R=$"tracing_fitEllipseTemp"/Q/A=(minArea)/F stats M_imageThresh
	//imageanalyzeparticles/E/Q/A=(minArea) stats M_imageThresh
	
	ellipse_momentsToCoords(nan,outRef_params,outRef_ellipse,inclParamDimLabels)		//
end


function tracing_calcEllipsePlots(winN)
	String winN
	
	Variable numEllipsePlotPoints = 100
	Variable numLayers = 2			//likely 2: one layer for x values, 1 layer for y values
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	WAVE/D combinedSegWv = $combinedSegRef
	Variable numRows = dimsize(combinedSegWv,0)	
	String plotWvRef = tracing_getPlottedEllipseWvName(winN)
	WAVE/D/Z plotWv = $plotWvRef
	if (!waveExists(plotWv))
		Make/O/D/N=(numRows,numEllipsePlotPoints,numLayers) $plotWvRef/wave=plotWv
	else
		if (dimsize(plotWv,0) != numRows)
			Redimension/N=(numRows,-1,numLayers) plotWv
		endif
		if (dimsize(plotWv,1) != numEllipsePlotPoints)
			Redimension/N=(-1,numEllipsePlotPoints,numLayers) plotWv
		endif
	endif
	
	Variable i
	Variable xCenter,yCenter,majorAxisRadius,minorAxisRadius,angle_rad
	Variable xCenter_P,yCenter_P,majorAxisRadius_P,minorAxisRadius_P,angle_rad_P
	xCenter_P=FindDimLabel(combinedSegWv,1,"xCenter")
	yCenter_P=FindDimLabel(combinedSegWv,1,"yCenter")
	majorAxisRadius_P=FindDimLabel(combinedSegWv,1,"majorAxisRadius")
	minorAxisRadius_P=FindDimLabel(combinedSegWv,1,"minorAxisRadius")
	angle_rad_P=FindDimLabel(combinedSegWv,1,"angle_rad")
	String outRef_params = ""		//pass null to skip storing params, which makes sense since they should have been calculated previously
	Variable inclParamDimLabels = 0		//only matters when outRef_params is not null
	String outRef_ellipse = "tracing_ellipsePlotTemp"
	for (i=0;i<numRows;i+=1)
		xCenter = combinedSegWv[i][xCenter_P]
		yCenter = combinedSegWv[i][yCenter_P]
		majorAxisRadius = combinedSegWv[i][majorAxisRadius_P]
		minorAxisRadius = combinedSegWv[i][minorAxisRadius_P]
		angle_rad = combinedSegWv[i][angle_rad_P]
		elipse_coords(xCenter,yCenter,majorAxisRadius,minorAxisRadius,angle_rad,numEllipsePlotPoints,outRef_params,outRef_ellipse,inclParamDimLabels)
		//if (i==0)
			WAVE/D ellipseTemp = $outRef_ellipse
		//endif
		plotWv[i][][0] = ellipseTemp[q][0]
		plotWv[i][][1] = ellipseTemp[q][1]
		if (i==1052)
			Print "xCenter",xCenter,"yCenter",yCenter,"majorAxisRadius",majorAxisRadius,"minorAxisRadius",minorAxisRadius,"angle_rad",angle_rad
		endif
	endfor
end

function nrn_tracing_toHoc(winN,neuron_name,xyMicronsPerPix,zMicronsPerPix,[alsoSaveWithSegAppendStr,saveWithSegAppendStr,fullPathStr,ssf])
	String winN,neuron_name
	Double xyMicronsPerPix,zMicronsPerPix		//saves from pixel measurements, so needs these conversion factors to save in microns
	String alsoSaveWithSegAppendStr		//optionally pass to also save a copy where all segment names have this string appended
												//useful for creating two copies of the cell for parallel fitting		..output file name also received append str
	String saveWithSegAppendStr			//as above but only save with segments names that have this string appended, do not save original segment names
	String fullPathStr
	Variable ssf		//same save folder for repeated saving
	
	String nlc = "\r\n"		//new line characters .. \r\n looks right in txt opened in notepad
	if (strlen(winN) < 1)
		winN = winname(0,1)
	endif
	
	if (strlen(neuron_name) < 1)
		neuron_name = tracing_getTracedWvNmFromWinN(winN)
	endif
	
	String segNameAppendStr=""
	if (!ParamIsDefault(saveWithSegAppendStr) && (strlen(saveWithSegAppendStr)>0) )
		segNameAppendStr=saveWithSegAppendStr
	endif

	Variable refNum
	String fileFilters = "Hoc Files (*.hoc):.hoc;"	
	if (!paramIsDefault(fullPathStr) && (strlen(fullPathStr)>0))
		newpath/o/q/z nrn_tracing_toHocPath,fullPathStr
		if (V_flag != 0)		//failed
			Open/F=fileFilters/M="Failed to store path after first save -- do manual"  refNum as "anat"+segNameAppendStr+".hoc"
		else
			Open/F=fileFilters/p=nrn_tracing_toHocPath refNum as "anat"+segNameAppendStr+".hoc"
		endif
	else
		pathinfo $"nrn_tracing_toHocPath"
		if (!paramIsDefault(ssf) && ssf && V_flag)
			Open/F=fileFilters/p=nrn_tracing_toHocPath refNum as "anat"+segNameAppendStr+".hoc"
		else
			Open/F=fileFilters refNum as "anat"+segNameAppendStr+".hoc"
		endif
	endif
	String saveFullPathStr = S_fileName
	if (!refNum)
		return -1
	endif
	
	variable i,j,numSpecLines = 2
	Make/t/o/n=(numSpecLines)/free specs
	specs[0] = "strdef neuron_name"
	specs[1] = "neuron_name = \"" + neuron_name +"\""
	String cs = "\tpt3dadd("		//command start: each point is specificed by starting with this prefix (a tab and then the command then open parenthesis)
	String ce = ")"+nlc				//command end: each point ends with close parenthesis and new line
	
	for (i=0;i<numSpecLines;i+=1)
		fprintf refNum,"%s%s",specs[i],nlc
	endfor
	
	fprintf refNum,"%s",nlc		//add a blank line
	
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String indexWvRef = tracing_getTracingIndexWaveRef(tracedwaveName)
	WAVE/T indexWv = $indexWvRef
	
	Variable numSegs = dimsize(indexWv,0),pnts
	Variable xPixLoc = 0, yPixLoc = 1, zPixLoc = 4,radiusPixLoc=6	//should match combined wave dim labels
	Double x0,y0,z0		
	Double xv,yv,zv,dv
	String segName,segref,line,lastSegName
	for (i=0;i<numSegs;i+=1)
		segName = indexWv[i][1]+segNameAppendStr
		segRef = indeXwv[i][0]
		WAVE seg = $segref
		pnts = dimsize(seg,0)
		fprintf refNum,"create %s%s",segName,nlc
		fprintf refNum,"%s {%s",segName,nlc		//start each segment specification with name {
		fprintf refNum,"\t%s%s","pt3dclear()",nlc	//then pt3dclear() command, using tabs for everything within the segment's brackets
		//print this sections points
		for (j=0;j<pnts;j+=1)
			if (j==0)			//the first point in each segment should connect to the previous one and should be a zero in relative coordinates
								//that's my take away, though its not really stated that clearly
								//here's the best refs. 
								//http://www.neuron.yale.edu/neuron/static/new_doc/modelspec/programmatic/topology/geometry.html#d-specification-of-geometry
								//http://www.neuron.yale.edu/phpBB/viewtopic.php?f=13&t=3277&p=13778&hilit=+pt3dadd+coordinates#p13778
				x0 = seg[j][xPixLoc]
				y0 = seg[j][yPixLoc]
				z0 = seg[j][zPixLoc]
			endif
			xv = (seg[j][xPixLoc]-x0)*xyMicronsPerPix		//current x,y,z values (as microns offset from first point)
			yv = (seg[j][yPixLoc]-y0)*xyMicronsPerPix
			zv = (seg[j][zPixLoc]-z0)*zMicronsPerPix
			dv = 2*seg[j][radiusPixLoc]*xyMicronsPerPix
			fprintf refNum, "%s%40.35f,%40.35f,%40.35f,%40.35f%s",cs,xv,yv,zv,dv,ce		
			
		endfor
		
		fprintf refNum,"}%s%s",nlc,nlc				//end each segment specification with } and a new line
		
		//connect segments to preceding segment unless its the first segment
		if (i > 0)
			lastSegName = indexWv[i-1][1]+segNameAppendStr
			fprintf refNum,"connect %s(0), %s(1)%s%s",segName,lastSegName,nlc,nlc		//prints the line then adds a space
		endif
	endfor		
	
	fprintf refNum,"define_shape()%s",nlc		//recommended to call this, no fucking clue what it does

	close refNum
	
	if (!ParamIsdefault(alsoSaveWithSegAppendStr) && (strlen(alsoSaveWithSegAppendStr)>0) )
		nrn_tracing_toHoc(winN,neuron_name,xyMicronsPerPix,zMicronsPerPix,saveWithSegAppendStr=alsoSaveWithSegAppendStr,fullPathStr=saveFullPathStr)
	endif

end


tracing_segToMask(winN,segNum)
	String winN
	Variable segNum
	
	String tracedWaveName = tracing_getTracedWvNmFromWinN(winN)
	String indexWvRef = tracing_getTracingIndexWaveRef(tracedwaveName)
	WAVE/T indexWv = $indexWvRef	
	String segName=indexWv[segNum]	
end

function tracing_fluor2D_intROI(traceWinN,fluorN,startPnt,maxCCPnt,negDir,euclidDistPix,euclidStepSizePix,outRef,micronsPerPixel,doDisplay,skipAnalysis,summaryRo,summaryCo,subrangeInfoWv,[forcedROIRef])
	String traceWinN		//window with tracing..assumes ROI is being traced and autoradius has been run
	String fluorN		//fluorescence trace to integrate
	Variable startPnt	//pnt EXACTLY AT start of ROI .. integration will begin here, but two points need to trail behind
	Variable maxCCPnt	//last point allowed..doesnt matter if approaching from below or above numerically
	Variable negDir		//can be before or ahead of startPnt
	Double euclidDistPix,euclidStepSizePix	//pixel step size
	String outRef		//holds results .. values for each slice, cumualtive values, average radius at slice
	Double micronsPerPixel		//only used to scale outputs to pixel space
	Variable doDisplay
	Variable skipAnalysis
	Variable summaryRo,summaryCo	//just automatically stick it in results for bookkeeping
	WAVE subrangeInfoWv		//row,col for start and ro col for end of region to even consider
	String forcedROIRef		//isntead of using ROI from tracing, force a different roi wave (helps avoid counting curling proximal axon segs near terminal)
	
	String tracedWaveName = tracing_getTracedWvNmFromWinN(traceWinN)
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	String radiusInfoRef = combinedSegRef+"_rad"
	WAVE/D ccWv=$combinedSegRef
	WAVE/D ccRad=$radiusInfoRef

	if (!PAramIsDefault(forcedROIRef))
		duplicate/o $forcedROIRef,myROIOverlayTemp0;
	else
		duplicate/o $tracedWAveName,myROIOverlayTemp0;
	endif
	redimension/n=(-1,-1) myROIOverlayTemp0	//need a copy of this, the ROI wave, to subtract counted areas to avoid double counting
	duplicate/o myROIOverlayTemp0,myROIOverlayTemp1,usedROITemp
	if (skipAnalysis)
		wave/D out=$outRef
		WAVE holderWv
	else
	
		Variable cc, step,endpnt
		if (negDir)
			step=-1
			endpnt=0
		else
			step=1
			endpnt=dimsize(ccwv,0)-1
		endif
		Variable xLocRow=FindDimLabel(ccWv, 1, "xPixLoc" )
		Variable yLocRow=FindDimLabel(ccWv, 1, "yPixLoc" )
		Variable radRow=FindDimLabel(ccWv, 1, "radiusPix" )
		Variable mRow=finddimlabel(ccRad,1,"m")
		Variable yIntRow=finddimlabel(ccRad,1,"yint")
		
		print "xLocRow",xLocRow,"yLocRow",yLocRow,"radRow",radRow,"mRow",mRow,"yIntRow",yIntRow,"combinedSegRef",combinedSegRef,"radiusInfoRef",radiusInfoRef
		Double xStart=ccwv[startPnt-2*step][xLocRow],yStart=ccwv[startPnt-2*step][yLocRow]
		
		StartPnt+=step	//need to iterate one so that the first point is always left of the line of interest
		Double xx0=ccwv[startPnt-step][xLocRow],yy0=ccwv[startPnt-step][yLocRow]	//fist iteration distance will evaluate to zero
		Double m0=ccRad[startPnt-step][mRow]
		Double rad0=ccwv[startPnt-step][radRow]
		Double ccDeltaDist		//incremental distance from last to next ccPnt
		Double ccDistToLast=0		//path length to last cc pnt
		Double ccDistToNext		//path length to next cc pnt
		Double intDistRelLast	//path length between last cc pnt and current loc of integration
		Double intDist=0	//integrated path length so far
		
		Duplicate/o $fluorN,$"fluor2d_intRoi_temp"/wave=sumWv,holderWv		//sumWv is the wave to sum, holderWv is a temp for calculation
		Make/o/d/n=(6) paramsHolderWvTemp
		
		Variable numSteps=floor((euclidDistPix/euclidStepSizePix))
		Variable stepCount=0
		make/o/d/n=(numSteps,7*2) $outRef/wave=out
		SetDimLabel 1,0,fluor_avg,out
		SetDimLabel 1,1,fluor_sum,out
		SetDimLabel 1,2,fluor_pnts,out
		SetDimLabel 1,3,fluor_var,out
		SetDimLabel 1,4,fluor_min,out
		SetDimLabel 1,5,fluor_max,out
		SetDimLabel 1,6,rad_avg,out
		dl_lblsToLbls(outRef,1,0,7,outRef,1,7,"_int",0)
		setscale/p x,0,euclidStepSizePix*micronsPerPixel,"p",out
	
		Double distToStep0=0
		Double distToStop1
		Double totalDist=0
		Double deltaDist,xx1,yy1,rad1,m1,propPastLast,weight0,weight1
		Double xAtInt,yAtInt,m_avg,yint_avg,rad_avg
		Double stepDist,currDist=0
	
		for (cc=startPnt;cc!=endpnt;cc+=step)
			if (cc==maxCCPnt)
				break
			endif
			xx1=ccwv[cc][xLocRow]
			yy1=ccwv[cc][yLocRow]
			rad1=ccwv[cc][radRow]
			m1=ccRad[cc][mRow]
			ccDeltaDist = sqrt( (xx1-xx0)^2 + (yy1-yy0)^2 )
			ccDistToNext = ccDistToLast + ccDeltaDist
			do 	//weight proportional to how far between each point we sit
				intDistRelLast = intDist - ccDistToLast
				propPastLast = intDistRelLast / ccDeltaDist
				if ( (propPastLast > 1) || (stepCount >= numSteps))
					break		//iterate ccPnt to get between the points that bound this intDist
				endif
				
				weight0 = 1- propPastLast		//e.g. if 25% thru this is 75%
				weight1 = propPastLast			//and this is 25%, add to one
				
				xAtInt=xx0*weight0+xx1*weight1
				yAtInt=yy0*weight0+yy1*weight1
				m_avg=m0*weight0 + m1*weight1	
				yint_avg=yAtInt-m_avg*xAtInt	//find y intercept for the line with average slope that crosses through these x,y coords
				rad_avg=(rad0*weight0+rad1*weight1)*micronsPerPixel	//average radius in pixels then convert to microns
				
				tracing_roiLineBisect(myROIOverlayTemp0,$fluorN,m_avg,yint_avg,xStart,yStart,holderWv,paramsHolderWvTemp,usedROITemp,subrangeInfoWv)
				out[stepCount][0]=paramsHolderWvTemp[0]		//avearge holderWv pixels (most useful)
				out[stepCount][1]=paramsHolderWvTemp[1]		//sum holderWv pixels
				out[stepCount][2]=paramsHolderWvTemp[2]		//pnts holderWv pixels
				out[stepCount][3]=paramsHolderWvTemp[3]		//variance holderWv pixels
				out[stepCount][4]=paramsHolderWvTemp[4]		//min holderWv pixels
				out[stepCount][5]=paramsHolderWvTemp[5]		//max holderWv pixels
				
				out[stepCount][6]=rad_avg		//store average radius
				//integrate cumulative for intensity and radius -- easier for calculating average
				if (stepCount == 0)
					out[stepCount][7,]=out[stepCount][q-7]//0
				else
					out[stepCount][7,]=out[stepCount-1][q]+out[stepCount][q-7]		//integrate
				endif
				myROIOverlayTemp0-=usedROITemp		//don't want to double count any pixels
				
				if (stepCount == 0)
					duplicate/o holderWv,myHolderTemp
					redimension/n=(-1,-1,1) myHolderTemp
				else
					concatenate/np=2  {holderWv},myHolderTemp
				endif
				//print "cc",cc,"intDist",intDist,"ccDistToLast",ccDistToLast,"ccDeltaDist",ccDeltaDist,"intDistRelLast",intDistRelLast,"propPastLast",propPastLast,"weight0",weight0,"weight1",weight1,"ccDistToNext",ccDistToNext,"m0",m0,"m1",m1,"m_avg",m_avg,"yint_avg",yint_avg,"xx0",xx0,"xx1",xx1,"xAtInt",xAtInt,"yy0",yy0,"yy1",yy1,"yAtInt",yAtInt
				print "cc",cc,"intDist",intDist,"ccDistToLast",ccDistToLast,"ccDeltaDist",ccDeltaDist,"intDistRelLast",intDistRelLast,"propPastLast",propPastLast,"weight0",weight0,"weight1",weight1,"ccDistToNext",ccDistToNext,"rad0",rad0,"rad1",rad1,"rad_avg",rad_avg
				intDist+=euclidStepSizePix
				stepCount+=1
			while ( stepCount < numSteps )		//break if we reach next ccPnt or reach end of distance
			
			if (stepCount >= numSteps)		//make sure we break out of this loop too
				break
			endif
			
			//prepare for next pnt
			xx0=xx1;yy0=yy1;m0=m1;rad0=rad1;ccDistToLast=ccDistToNext
		endfor
		
		if (cc == endPnt)
			Print "Hit last ccPnt!!"
		endif
		
		if (stepCount != numSteps)		//finished "prematurely"
			redimension/n=(stepCount-1,-1) out
		endif
	endif //end skip analysis
	
	if (doDisplay)
		display/k=1 out[][7]; String win=s_name; appendtograph/l=left1/w=$win out[][0]; appendtograph/r/w=$win out[][6];modifygraph/w=$win freepos=0,lblpos=50;modifygraph/w=$win freepos(left1)=40
		ModifyGraph/w=$win rgb(euclid#1)=(0,0,0),rgb(euclid#2)=(1,12815,52428)
		Label/w=$win right "\\K(1,12815,52428)Radius (μm)";Label/w=$win bottom "Path distance (μm)\\u#2"
		
		newimage/k=1 myHolderTemp;win=S_name;dowindow/f $win;doupdate;Execute/P/Q/Z "WMAppend3DImageSlider()";doupdate;	//use macro to append slider
		appendimage/w=$win $fluorN
		appendimage/w=$win myROIOverlayTemp1
		make/u/i/n=(2,4)/o myScreen;myScreen=0;myscreen[0][3]=.5*2^16;myscreen[1][3]=0///black and almost opaque at values of zero and black but transparent at values of 1
		ModifyImage/w=$win myROIOverlayTemp1 cindex= myScreen
		ModifyImage/w=$win myHolderTemp minRGB=NaN,maxRGB=NaN, ctab= {1,2201,Red,0}
		//ReorderImages/w=$win myHolderTemp,{$fluorN,$tracedWAveName}
		//String cmd="ReorderImages/w="+win+" myHolderTemp,{"+fluorN+","+"myROIOverlayTemp1};ModifyImage/w="+win+"myHolderTemp minRGB=NaN,maxRGB=NaN, ctab= {1,2201,Red,0}"
		//execute/p/q/z cmd
		PRint "run: ","ReorderImages/w="+win+" myHolderTemp,{"+fluorN+","+"myROIOverlayTemp1};ModifyImage/w="+win+" myHolderTemp minRGB=NaN,maxRGB=NaN, ctab= {1,2201,Red,0}"	//error and doesnt all take in commands even macro somehow
		
	endif
	
	Variable finalStepCount=dimsize(out,0)
	String paramsRef=outRef+"_P"
	Variable numParams=18
	make/o/d/n=(numParams) $paramsref/wave=outp
	Variable pedWinStart=0, pedWinEnd=6,axWinStart=pedWinEnd, axWinEnd=8// pedWinEnd=8,axWinStart=pedWinEnd, axWinEnd=13
	axWinEnd=min(finalStepCount,axWinEnd)
	Variable axWinStart_P=x2pnt(out, axWinStart),axWinEnd_P=x2pnt(out, axWinEnd),pedWinStart_P=x2pnt(out, pedWinStart),pedWinEnd_P=x2pnt(out, pedWinEnd)
	
	matrixop/o/free region=subrange(out,pedWinStart_P,pedWinEnd_P,0,0)		//average fluorescence
	Double pedFluor_avg=mean(region)
	Variable pedWin_pnts=dimsize(region,0)
	matrixop/o/free region=subrange(out,pedWinStart_P,pedWinEnd_P,6,6)		//average fluorescence
	Double pedRad_avg=mean(region)
	Double pedMin=wavemin(region)
	Double pedMax=wavemax(region)
	matrixop/o/free region=subrange(out,axWinStart_P,axWinEnd_P,0,0)		//average fluorescence
	Double axFluor_avg=mean(region)
	Variable axWin_pnts=dimsize(region,0)
	matrixop/o/free region=subrange(out,axWinStart_P,axWinEnd_P,6,6)		//average fluorescence
	Double axRad_avg=mean(region)
	Double axMin=wavemin(region)
	Double axMax=wavemax(region)
	
	Variable ii
	ii=0;dl_assignAndLbl(outp, ii, axWinStart, "axWinStart")
	ii+=1;dl_assignAndLbl(outp, ii, axWinEnd, "axWinEnd")
	ii+=1;dl_assignAndLbl(outp, ii, axWinStart_P, "axWinStart_P")
	ii+=1;dl_assignAndLbl(outp, ii, axWinEnd_P, "axWinEnd_P")
	ii+=1;dl_assignAndLbl(outp, ii, pedWinStart, "pedWinStart")
	
	ii+=1;dl_assignAndLbl(outp, ii, pedWinEnd, "pedWinEnd")
	ii+=1;dl_assignAndLbl(outp, ii, pedWinStart_P, "pedWinStart_P")
	ii+=1;dl_assignAndLbl(outp, ii, pedWinEnd_P, "pedWinEnd_P")
	ii+=1;dl_assignAndLbl(outp, ii, pedWin_pnts, "pedWin_pnts")
	ii+=1;dl_assignAndLbl(outp, ii, pedFluor_avg, "pedFluor_avg")
	
	ii+=1;dl_assignAndLbl(outp, ii, pedRad_avg, "pedRad_avg")
	ii+=1;dl_assignAndLbl(outp, ii, axWin_pnts, "axWin_pnts")
	ii+=1;dl_assignAndLbl(outp, ii, axFluor_avg, "axFluor_avg")
	ii+=1;dl_assignAndLbl(outp, ii, axRad_avg, "axRad_avg")	
	ii+=1;dl_assignAndLbl(outp, ii, pedMin, "pedMin")
	
	ii+=1;dl_assignAndLbl(outp, ii, pedMax, "pedMax")
	ii+=1;dl_assignAndLbl(outp, ii, axMin, "axMin")
	ii+=1;dl_assignAndLbl(outp, ii, axMax, "axMax")//18
	
	if (!numtype(summaryRo) && !numtype(summaryCo))
		WAVE ctbp2results
		ctbp2results[summaryRo][summaryCo,summaryCo+numParams-1] = outp[q-summaryCo]
	endif
	
	redimension/n=4 subrangeinfowv
	redimension/n=(numParams+4) outp
	outp[numparams,]=subrangeinfowv[p-numparams]
	
	if (doDisplay)
		edit/k=1 outp.ld
	endif
end

//SUGGESTED UTILITY: IF YOU WANT TO INTEGRATE ACROSS sumWV, SUBTRACT THE OUTPUT WAVE BEFORE CALLING NEXT
//THAT WAY NO PIXEL IS DOUBLE COUNTED
function tracing_roiLineBisect(roiWv,sumWv,m,yint,px,py,holderWv,paramsWv,usedROIWave,subrangeInfoWv)
	WAVE roiWv		//wave specifying region of interest as 1, non region of interest as zero
	WAVE sumWv		//wave to integrate all points on side of line of px,py
	Double m,yint		//line equation
	Double px,py			//position of a point on the side of the line to keep
	WAVE holderWv		//for looping, ideally pre-isntantiate
	WAVE/d paramsWv		//for looping, ideally pre-instantiated
	WAVE usedROIWave
	WAVE subrangeInfoWv		//row,col for start and ro col for end of region to even consider
	
	Variable startCol,startRow
	Variable endCol,endRow
	if (dimsize(subrangeinfowv,0) < 4)
		startRow=0
		startCol=0
		endRow=dimsize(roiWv,0)-1
		endCol=dimsize(roiWv,1)-1
	else
		startRow=subrangeinfowv[0]
		startCol=subrangeinfowv[1]
		endRow=subrangeinfowv[2]-1
		endCol=subrangeinfowv[3]-1	
	endif
	
	if (!WaveExists(holderWv))
		duplicate/o sumWv,holderWv;
	endif
	if (!waveExists(usedROIWave))
		duplicate/o roiWv,usedROIWave
	endif
	
	duplicate/o/free/r=(*) holderWv,countWv		//one row long count wave
	redimension/n=(-1) countWv
	countWv=0
	
	Double lineXValAtPntY = (py-yint)/m
	Variable pointOnRight = lineXValAtPntY < px
	Variable correctSideValue = 1
	Variable wrongSideValue = 0
	Variable rightValue = pointOnRight ? correctSideValue : wrongSideValue
	Variable leftValue = pointOnRight ? wrongSideValue : correctSideValue
	//print "pointOnRight",pointOnRight,"correctSideValue",correctSideValue,"wrongSideValue",wrongSideValue,"rightValue",rightValue,"leftValue",leftValue
	Variable rows=dimsize(roiWv,0)		//rows increase along horizontal
	Variable cols=dimsize(roiWv,1),yScale=dimdelta(roiWv,1)		//cols increase along vertical
	variable xx=0,yy=yscale*startCol
	
	holderWv=wrongSideValue
	usedROIWave=0
	
	variable i,j
	Double currLineXValAtPntY
	Double count=0,value,currCount
	for (j=startCol;j<endCol;j+=1)
		currLineXValAtPntY = (yy-yint)/m
		countWv[startRow,endRow]= (x<currLineXValAtPntY ? leftValue : rightValue) * roiWv[p][j]
		currCount=sum(countWv,startRow,endRow)		//only pay attention to points that were considered
		usedROIWave[startRow,endRow][j]=countwv[p]
		if (currCount>0)
			holderWv[startRow,endRow][j]= countWv[p] * sumWv[p][j]// * roiWv[p][j]
			count += currCount
		endif
		
		yy+=yScale
	endfor
	
	if (!WaveExists(paramsWv))
		make/o/d/n=(6) paramsWv
	endif	
	
	Double total=sum(holderWv)
	Double avg = (count == 0) ? 0 : total/count
	paramsWv[1] = total
	paramsWv[0] = avg
	paramsWv[2] = count
	paramsWv[3] = variance(holderWv)
	paramsWv[4] = wavemin(holderWv)		//THINK these are multidimensional ok if you don't care about position
	paramsWv[5] = wavemax(holderWv)	
	return paramsWv[0]
end

//add to a graph being used for tracing (setwindow $"" winhook(tracing_simpleCsrFollowPntHook)=tracing_simpleCsrFollowPntHook)
//and then any graphs plotting the combinedSegRef / combinedSegWv will get a csr on the current cc pnt
function tracing_simpleCsrFollowPntHook(s)
	STRUCT WMWinHookStruct &s
	
	String winN = s.winName
		
	Variable selPnt_overallIndex = tracing_getSelPntData(winN,nan)
	//Variable selPnt_segIndex = tracing_getSegPntNumForCCPnt(winN,selPnt_overallIndex)
	//Variable selPntSegNum = tracing_getSegNumForCCPnt(winN,selPnt_overallIndex)
		
	String tracedWaveName = img_getImageName(winN)	
	String combinedSegRef = tracing_getCombinedSegref(tracedWaveName)
	
	if (!WaveExists($combinedSegRef))
		return 0
	endif	
		
	String graphsWithCCWave = disp_getWinListForWv(combinedSegRef,forceWinTypes=1),graph
		
	Variable i,num=itemsinlist(graphsWithCCWave)
	for (i=0;i<num;i+=1)
		graph=stringfromlist(i,graphsWithCCwave)
		Cursor/A=1/P/W=$graph A,$combinedSegRef,selPnt_overallIndex
		showinfo/W=$graph
	endfor
	
	return 0
end

//use this function in case you know the name of the window that was attempted to be used originally
//and to which Igor may have added numbers afterwards
//not a perfect function because this will also return longer names
function/S win_getFirstDerivedWinName(parentWinN)
	String parentWinN

	String wins = winList(parentWinN + "*",";","")		//list of all windows matching name with anything following
	
	//only those wins with one or more digits following name
	//avoids non-digit etc. after the parentWinN that would indicate a window name
	//that contains parentWinN but has a longer, different name
	//based on this example from the help files:
	
//	Function DemoSplitString()
//	String subject = "Thursday, May 7, 2009"
//	String regExp = "([[:alpha:]]+), ([[:alpha:]]+) ([[:digit:]]+), ([[:digit:]]+)"
//	String dayOfWeek, month, dayOfMonth, year
//	SplitString /E=(regExp) subject, dayOfWeek, month, dayOfMonth, year
//	Print dayOfWeek, month, dayOfMonth, year
//	End
//	The output from Print is:
//	Thursday  May  7  2009	
	
	Variable i, followingNum
	Variable valueOfLowestRepFound = inf
	Variable indexOfLowestRepFound = NaN
	String currN, trailingText, followingNumStr
	
	String regExp = "parentWinN" + "([[:digit:]]+)([[:alpha:]]+)"
	for (i=0;i<ItemsInList(wins);i+=1)
		currN = StringFromList(i, wins)
		
		if (strlen(currN) == strlen(parentWinN))
			return parentWinN
		endif
		
		SplitString/E=(regExp) currN, followingNumStr, trailingText
		
		if (strlen(followingNumStr) && !strlen(trailingText))	//then there is length to followingNumStr, so see if this is the lowest numbered match
			followingNum = str2num(followingNumStr)
		
			if (followingNum < valueOfLowestRepFound)
				indexOfLowestRepFound = i
			endif
			
		endif
	
	endfor
	
	if (numtype(indexOfLowestRepFound))	//check if indexOfLowestRepFound still inf, if so return empty bc nothing found 
		return ""
	endif
	
	return StringFromLisT(indexOfLowestRepFound,wins)
end

function/S text_increment(text, V_increment)
	String text; Variable V_increment
	
	return num2str(str2num(text) + V_increment)
end

function wave_valueThreshold(origVal, adjustedMin, adjustedMax, scaleFactor, rangeMin, rangeMax, valBelowMin, valAboveMax, gammaVal)
	Variable origVal, adjustedMin, adjustedMax, scaleFactor
	Variable rangeMin, rangeMax	//cut off thresholds, valBelowMin set for below min, valBelowMax for above
	Variable valBelowMin, valAboveMax
	Variable gammaVal
	
	Variable result =  (origVal - adjustedMin) * scaleFactor 
	
	if (result < rangeMin)
		return valBelowMin
	endif
	if (result > rangeMax)
		return valAboveMax
	endif
	
	if (  ((result / (rangeMax - rangeMin))^gammaVal)	> 1)
		Print "gamma output greater than 1!"
		if ( (result / (rangeMax - rangeMin)) > 1)
			Print "gamma input greater than 1!"
		endif
	endif
	
	//		(input normalized to range)^gamma	--this a value between 0 and 1			// which is multiplied back onto the full range by the right hand side
	result = ((result / (rangeMax - rangeMin))^gammaVal)			* (rangeMax - rangeMin)
		
	return result
end


function/S wave_colList(wv,colLbl,includeRules,matchAllIncludeRules,excludeRules,includeBlanks,[layer])
	WAVE/T wv
	String colLbl				//label of column of data to return or "" to receive list of associated row labels
	String includeRules		//include waves matching these rules (semi-colon between rules), each rule is colLbl,matchStr. Optionally colLbl,matchStr,layer for non zero layer
	Variable matchAllIncludeRules		//0 include matches to one or more rules, 1 to include only matches to all rules
	String excludeRules		//exclude waves matching these rules (semi-colon between rules), each rule is colLbl,matchStr. Optionally colLbl,matchStr,layer for non zero layer
	Variable includeBlanks	//0 to remove blanks from output, 1 to include
	Variable layer
	
	Variable outLayer = (PAramIsDefault(layer) || (numtype(layer)>0)) ? 0 : layer
	
	String out="",itemStr=""
	
	Variable returnRowLbls=strlen(colLbl) < 1
	
	Variable col= returnRowLbls ? nan : finddimlabel(wv,1,colLbl) 
	Variable i,rows=dimsizE(wv,0),j,ruleCol
	Variable numIncludeRules=itemsinlist(includeRules)
	Variable hasIncludeRules=numIncludeRules>0
	Variable numExcludeRules=itemsinlist(excludeRules)
	String rule,ruleMatchStr,ruleLbl,valStr
	Variable numIncludeMatches,ruleMatch,ruleLayer,exclude
	for (i=0;i<rows;i+=1)
		//check include rules
		numIncludeMatches=0
		for (j=0;j<numIncludeRules;j+=1)
			rule=c2sc(stringfromlist(j,includeRules))
			ruleLbl=stringfromlist(0,rule)
			ruleCol=finddimlabel(wv,1,ruleLbl)
			if (ruleCol < 0)
				print "wave_colList() failed to find include rule",ruleLbl,"which was including matches to=",ruleMatchStr
				return ""
			endif
			ruleMatchStr=stringfromlist(1,rule)
			ruleLayer = (itemsinlist(rule) > 2) ? str2num(stringfromlist(2,rule)) : 0
			valStr=wv[i][ruleCol][ruleLayer]
			ruleMatch=stringmatch(valStr,ruleMatchStr)
			numIncludeMatches+=ruleMatch
		endfor
		if (hasIncludeRules && numIncludeMatches==0)		//include rules ignored if not passed
			continue
		endif
		if (matchAllIncludeRules && (numIncludeMatches!=numIncludeRules) )
			continue
		endif
		
		//check exclude rules
		exclude=0
		for (j=0;j<numExcludeRules;j+=1)
			rule=c2sc(stringfromlist(j,excludeRules))
			ruleLbl=stringfromlist(0,rule)
			ruleCol=finddimlabel(wv,1,ruleLbl)
			if (ruleCol < 0)
				print "wave_colList() failed to find exclude rule",ruleLbl,"which was excluding matches to=",ruleMatchStr
				return ""
			endif
			ruleMatchStr=stringfromlist(1,rule)
			ruleLayer = (itemsinlist(rule) > 2) ? str2num(stringfromlist(2,rule)) : 0
			valStr=wv[i][ruleCol][ruleLayer]
			ruleMatch=stringmatch(valStr,ruleMatchStr)
			if (ruleMatch)
				exclude=1
				break	
			endif
		endfor		
		
		if (exclude)
			continue
		endif
		
		if (returnRowLbls)
			itemStr=getdimlabel(wv,0,i)
		else
			itemStr=wv[i][col][outLayer]
		endif
		
		if (includeBlanks || (strlen(itemStr)>0) )
			out+=itemStr+";"	
		endif
	endfor
	
	return out
end


function/S wave_dupWavesInWin(matchStr,replaceThisStr,withThisStr)
	String matchStr
	String replaceThisStr,withThisStr
	
	String list = wavelist(matchStr,";","WIN:")		//top window
	
	String changedList = wave_dupWithStrReplacedName(list,replaceThisStr,withThisStr)
	
	Variable i,numWvs = itemsinlist(changedList)
	
	for (i=0;i<numWvs;i+=1)
		ReplaceWave/W=$winName(0,1) trace=$StringFromList(i,list) $stringfromlist(i,changedlist)
	endfor
end

function/S wave_dupWithStrReplacedName(listOfWaves,replaceThisStr,withThisStr)
	String listOfWaves
	String replaceThisStr, withThisStr
		
	String outList = ""
	
	Variable i; String newName, oldName
	for (i=0;i<ItemsInList(listOfWaves);i+=1)
		oldName = StringFromList(i, listOfWaves)
		newName = ReplaceString(replaceThisStr, oldName, withThisStr)
		outList += newName + ";"
		if (!stringmatch(oldName,newName))
			Duplicate/O $oldName, $newName
		endif
	endfor
	
	Print "wave_dupWithStrReplacedName(): COPIED WAVES IN LIST TO NEW REFS AS (original names then new names follow):" 
	Print "listOfWaves",listOfWaves,"outList",outList
	return outList
end


function wave_getTotalDist_1D(ref)
	String ref
	
	WAVE temp = $ref
	
	Variable i, total=0
	for (i=1;i<DimSize(temp,0);i+=1)
		total += abs(temp[i] - temp[i-1])
	endfor
	
	return total
	
end


function wave_getTotalDist_3D(ref0,ref1,ref2,[endRow,xyzInds,sumByPntOutRef])
	String ref0, ref1, ref2	//refs to (1D) waves with x,y,z and z point locations, one row for each point, rows matched between xyz waves
	Variable endRow	//optionally pass an end row
	Wave xyzInds		//optionally pass xyz ind wave and then only ref0 is used at x=ref0[xyzInds[0]],y=ref0[xyzInds[1]],z=ref0[xyzInds[2]]
	STring sumByPntOutRef
	
	WAVE temp0 = $ref0
	Variable i,rows=DimSize(temp0,0),storeSum=0
	Double totalDist=0,currDist
	if (!paramIsDefault(sumByPntOutRef) && (strlen(sumByPntOutRef)>0))
		make/o/d/n=(rows) $sumByPntOutRef/wave=out
		out[0]=0
		storeSum=1
	endif
	if (ParamIsDefault(endRow))
		endRow=rows
	endif
	
	if (PAramIsDefault(xyzInds))
		WAVE temp1 = $ref1; WAVE temp2=$ref2
		for (i=1;i<rows;i+=1)
			if (i>endRow)
				break
			endif
			currDist=sqrt(     ((temp0[i] - temp0[i-1])^2) + ((temp1[i] - temp1[i-1])^2) + ((temp2[i] - temp2[i-1])^2)     )
			totalDist += currDist
			if (storeSum)
				out[i]=totalDist
			endif			
		endfor
	else
		Variable xCol=xyzInds[0],yCol=xyzInds[1],zCol=xyzInds[2]
		for (i=1;i<rows;i+=1)
			if (i>endRow)
				break
			endif
			currDist=sqrt(     ((temp0[i] - temp0[i-1])^2) + ((temp1[i] - temp1[i-1])^2) + ((temp2[i] - temp2[i-1])^2)     )
			totalDist += currDist
			if (storeSum)
				out[i]=totalDist
			endif	
		endfor
	endif
	
	return totalDist
	
end


//fit a plateau that rises to one and then falls back to zero in the same time constant
//free parameters are rising and falling x position and the tau
function fit_simpleSigmoids(w,x) : FitFunc	//returns exptest = 1/(1+exp(-(x-x0)/tau))-1/(1+exp(-(x-x1)/tau))
	WAVE w	//contains tau
	Variable x
	
	return 1/(1+exp(-(x-w[1])/w[0]))-1/(1+exp(-(x-w[2])/w[0]))
end

function fit_getSimpleSigmoids(inRef,tauGuess,x0Guess, x1Guess,outCoefsRef,outFitRef,appendToGraphStr)
	String inRef,outFitRef	//ref to fit and fit to save fit to
	String outCoefsRef	//ref to save coefs to
	String appendToGraphStr		//graph name to plot to or "" for none... input winname(0,1) for top graph
	Double tauGuess,x0Guess, x1Guess		//standard values (e.g. from mike's 2009 paper are 12.2*10^-12, 12.9, 1.3 (Mike has fast and slow switched in his figure 2 legend)
	
	Make/O/D/N=3 $outCoefsRef/wave=outCoefsWv
	outCoefsWv[0] = tauGuess;setdimlabel 0,0,tauGuess,outCoefsWv
	outCoefsWv[1] = x0Guess;setdimlabel 0,0,x0Guess,outCoefsWv
	outCoefsWv[2] = x1Guess;setdimlabel 0,0,x1Guess,outCoefsWv
	
	FuncFit/N=1/Q/W=2 fit_simpleSigmoids,outCoefsWv,$inRef

	if (strlen(outFitRef))
		Duplicate/O $inRef, $outFitRef/wave=outFitWv
		outFitWv = fit_simpleSigmoids(outCoefsWv,x)
		
		
		if (strlen(appendToGraphStr))
			appendToGraph/W=$appendToGraphStr outFitWv
		endif
	endif
end
