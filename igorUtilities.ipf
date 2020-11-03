#pragma TextEncoding = "UTF-8" 
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

//general helper procs

//A procedure for repetitive operations (that can't be made into implicit loops in wave assignments)
//iterates through a list (strList parameter), substituting any %s in executeStr with the current list item
//and substituting any %i with the current list index, then executing executeStr.
//Optionally instead iterate over certain waves (over a single row or single column of a 2D wave)
//Optionally pass alternative escape strings instead of %s and %i (altItemEscapeStr and altIndexEscapeStr, respectively)
//optionally pass the name of a global string that is used in loop (e.g., "returnStr+=%s_transformed;"), pass returnStr=returnStr. the global is created if it does not exist
function/S list_operation_g(executeStr,strList,[start,num,delim,iterateWaveColInstead,iterateWaveRowInstead,replaceStr,skipBlanks,checkVarName,extraLists,altItemEscapeStr,altIndexEscapeStr,toClip,memChecks,returnStr,clearReturnStrAtStartOrEnd])
	String executeStr		//macro to execute e.g, display/k=1 %s to plot waves named in strList
	String strList		//semicolon-delimited list to iterate over (e.g., names of waves), or "" to just use %i, or the name of a wave to use either iterateWaveColInstead,iterateWaveRowInstead
	Variable start,num		//for specifying a subrange of strList
	variable iterateWaveColInstead	//optionally pass to iterate down a wave column, column number is passed and wave name is in strList.. pass -1 to use row labels
	Variable iterateWaveRowInstead	//optionally pass to iterate across a wave row..row number is passed here, pass -1 to use row labels
	String delim		//expects semi-colon delimited strList, pass to use another delimiter
	String replaceStr		//optionally pass a replace string in the form of "replaceThisStr;withThisStr" for each list item
								//if passed, any %r will be replaced with replacestring(replaceThisString,listItem,withThisString)
	String altItemEscapeStr	//optionally pass a different string that list items will replace (instead of %s)
	String altIndexEscapeStr		//optionally pass a different string that list indicies will replace (instead of %i)
								//sometimes it is useful to override the defaults (e.g., dimension labels starting with s), to do so pass "escapeStrName0,altEscapeStr0;escapeStrName1,altEscapeStr1;..." etc.
	Variable skipBlanks		//pass 1 to skip blank strings in strList, these blanks will also be ignored for %i, which will continue to track the list index, unless skipBlanks==2
	String extraLists		//pass extra lists that will replaced %0s,%1s,%2s, etc based on the position in this list of lists. The main position is "|" delimited. Within each list, ";" is used or delim if passed. Currently can't use a different escape string
	String checkVarName		//optionally pass the name of a num variable that might get changed to false during your executeStr execution. If passed, the function will break if ever the num is false after an execution
	int toClip				//send commands to clip
	int memChecks			//check for memory below 0.1 GB and abort if below
	String returnStr	//optionally pass the name of a global string that is used in loop (e.g., "returnStr+=%s_transformed;"), fr which you would pass returnStr=returnStr. the global is created if it does not exist. defaults to returnStr if passing ""
	int clearReturnStrAtStartOrEnd  //pass -1 to clear at start, 1 to clear at end, or zero for neither
	
	//handle some optional parameters
	int doToClip = !ParamIsDefault(toClip) && toClip
	int doMemChecks = !ParamIsDefault(memChecks) && memChecks
	String itemEscapeStr = "%s"		//default list item escape string  
	String indexEscapeStr = "%i"			//default list index escape string
	if (!ParamIsDefault(altItemEscapeStr) && (strlen(altItemEscapeStr) > 0) )
		itemEscapeStr = altItemEscapeStr
	endif
	if (!ParamIsDefault(altIndexEscapeStr) && (strlen(altIndexEscapeStr) > 0) )
		indexEscapeStr = altIndexEscapeStr
	endif
	if (!ParamIsDefault(returnStr))
		if (strlen(returnStr)<1)
			returnStr="returnStr"
		endif
		SVAR/z returnStrLocal = $returnStr
		if (!svar_exists(returnStrLocal))
			string/g $returnStr; SVAR returnStrLocal = $returnStr
		endif
		
		if (clearReturnStrAtStartOrEnd < 0)
			returnStrLocal=""
		endif
	endif
								
	Variable doCheckVar = !ParamIsDefault(checkVarName) && (strlen(checkVarName) > 0)
	if (doCheckVar)
		NVAR/Z checkVar = $checkVarName
		if (!Nvar_exists(checkvar))
			doCheckVar=0
			print "failed to find existing checkvar named",checkvarname
		endif
	endif
	
	Variable numExtraLists = (ParamIsDefault(extraLists) || (strlen(extraLists) < 1)) ? 0 : itemsinlist(extraLists,"|")
	if (numExtraLists > 0)
		WAVE/t extraListsWv = listtotextwave(extraLists,"|")
	endif
	Variable doSkipBlanks = !ParamIsDefault(skipBlanks) && (skipBlanks>0)
	Variable skippedBlanksCountTowardsInds = doSkipBlanks && (skipBlanks==2)
	
	String delimUsed
	if (ParamIsDefault(delim))
		delimUsed=";"
	else
		delimUsed=delim
	endif
	
	//handle iterating through a wave row or column
	Variable i,ind; String currExecuteStr, listStr,ref
	if (!ParamIsDefault(iterateWaveColInstead) && !numtype(iterateWaveColInstead) && (iterateWaveColInstead>-2))	//column iteration
		ref=strList
		WAVE/T wv=$strList		//needs error checking
		strList=""
		Variable rows=dimsize(wv,0)
		if (iterateWaveColInstead < 0)	//==-1 so row labels
			for (i=0;i<rows;i+=1)
				strList+=getdimlabel(wv,0,i)+delimUsed
			endfor		
		else
			for (i=0;i<rows;i+=1)
				strList+=wv[i][iterateWaveColInstead]+delimUsed
			endfor
		endif
	elseif (!ParamIsDefault(iterateWaveRowInstead) && !numtype(iterateWaveRowInstead) && (iterateWaveRowInstead>-2))	//row iteration
		ref=strList
		WAVE/T wv=$strList			//needs error checking
		strList=""
		Variable cols=dimsize(wv,1)
		if (iterateWaveRowInstead < 0)	//==-1 so row labels
			for (i=0;i<cols;i+=1)
				strList+=getdimlabel(wv,1,i)+delimUsed
			endfor		
		else
			for (i=0;i<cols;i+=1)
				strList+=wv[iterateWaveRowInstead][i]+delimUsed
			endfor
		endif
	endif
	
	Variable startInd = ParamIsDefault(start) ? 0 : start
	Variable numItems=ItemsInList(strList,delimUsed) 
	Variable maxItems=numItems-startInd
	Variable numInds
	if ( (strlen(strList) < 1) && !ParamisDefault(num) )
		numInds = num
	else
		numInds = ParamISDefault(num) ? maxItems : min(startInd+num,maxItems) 
	endif
	
	Variable skips=0,printInd,j
	String extraListStr
	for (i=0;i<numInds;i+=1)
		//calculate index (printInd is actually used in executeStr
		ind=i+startInd
		listStr=stringfromlist(ind,strList,delimUsed)
		if ( doSkipBlanks && (strlen(listStr) < 1) )
			skips+=1
			continue
		endif
		printInd = ind - skippedBlanksCountTowardsInds*skips		//skips will be zero if no skipping blanks or skipped blanks aren't counting towards printed index
		
		//make executeStr
		currExecuteStr = replacestring(itemEscapeStr,executeStr,listStr,1)
		currExecuteStr = replacestring(indexEscapeStr,currExecuteStr,num2str(printInd),1)

		for (j=0;j<numExtraLists;j++)
			extraListStr = stringfromlist(ind,extraListsWv[j],delimUsed)
			currExecuteStr = replacestring("%"+num2str(j)+"s",currExecuteStr,extraListStr)
		endfor
		
		Execute/q currExecuteStr
		if (doToClip)
			putscraptext currExecuteStr
		endif
		
		if (doCheckVar)
			if (!checkVar)
				//print "list_operation_g() aborting as checkVar is now false. var name=",checkvarname,"iteration",i
				break
			endif
		endif
		
		if (doMemChecks)
			Double freeMem=GetFreeMemoryInGb()
			if (freeMem < 0.2)
				print "list_operation_g() aborting on nearly-out-of-memory warning!","iteration",i
				break
			endif
		endif
		
	endfor
	
	if (!ParamIsDefault(returnStr))
		String localTemp = returnStrLocal
		if (clearReturnStrAtStartOrEnd > 0) 
			returnStrLocal=""
		endif
		return localTemp
	else
		return ""
	endif
end
 

//assign multiple dimension labels from a String list
function dl_assignLblsFromList(wv,dim,startIndex,list,appendStr,appendBeforeLblNotAfter[reuseLast])
	WAVE wv		//wave to label
	int dim		//dim to label
	int startIndex	//index to start at in dim to label (end index is based on length of list)
	String list			//list of labels to assign, semi-colon delimited
	String appendStr		//optionally append a string to all labels
	int appendBeforeLblNotAfter		//put appendStr before (1) or after (0) the rest of the label
	int reuseLast		//optionally pass true to coninue using the last in the list until the end of the dimension
	
	int i,num=itemsinlisT(list),maxIndex = dimsize(wv,dim),index=startIndex
	String lb=stringfromlist(0,list)
	for (i=0;index<maxIndex;i++)		//iterate from startIndex to end of dimension
	
		//check for end of list, if so break unless reuseLast is true
		if (i >= num)
			if (ParamIsDefault(reuseLast) || !reuseLast)
				break
			endif
			SetDimLabel dim,index,$lb,wv
		else
		
		//usual case, get label from list and add appendStr
			if (appendBeforeLblNotAfter)
				lb=appendStr + stringfromlist(i,list)
			else
				lb=stringfromlist(i,list) + appendStr
			endif
			
		endif
		
		SetDimLabel dim,index,$lb,wv
		index++	//index is always i+startIndex
	endfor
	
	return i
end


function dl_lblsToLbls(fromWvRef,fromDim,from_startIndex,num,toWvRef,toDim,to_startIndex,to_appendLabel,appendBeforeNotAfter,[forceToWv,forceFromWv,replaceStr0WithStr1])
	String fromWvRef,toWvRef
	Variable fromDim,toDim		//dimension to transfer from and to
	Variable num	//num to transfer
	Variable from_startIndex, to_startIndex		//index to start at for transferring from and to .. currently no bounds checking except for both start indices = 0, so run time error will occur if out of bounds
	String to_appendLabel		//pass to add some text after the label
	Variable appendBeforeNotAfter	//pass true to add string in to_appendLabel before rather than after the label
	WAVE forceFromWv,forceToWv		//optionally pass a wave instead. useful for free waves
	String replaceStr0WithStr1		//pass string0;string1 to replace string0 with string1 in each label
	
	int doReplace = !ParamIsDefault(replaceStr0WithStr1) && (itemsinlist(replaceStr0WithStr1) > 1)
	String replaceThisStr,withThisStr
	if (doReplace)
		replaceThisStr=stringfromlist(0,replaceStr0WithStr1)
		withThisStr=stringfromlist(1,replaceStr0WithStr1)
	endif

	if (ParamIsDefault(forceFromWv))
		WAVE fromWv = $fromWvRef
	else
		WAVE fromWv=forceFromWv
	endif
	if (ParamIsDefault(forceToWv))
		WAVE toWv = $toWvRef
	else
		WAVE toWv=forceToWv
	endif
	
	if (numtype(toDim))
		toDim = fromDim
	endif
	
	if (to_startIndex < 0)
		to_startIndex = 0
	endif
	
	Variable i
	if (numtype(num))
		num = min(dimsize(fromWv,fromDim)-from_startIndex,dimsize(toWv,toDim)-to_startIndex)
	endif
	
	String lbl
	if (appendBeforeNotAfter)
		for (i=0;i<num;i+=1)
			lbl=GetDimLabel(fromWv, fromDim, i+from_startIndex)
			if (doReplace)
				lbl=ReplaceString(replaceThisStr,lbl,withThisStr)
			endif
			SetDimLabel toDim,i+to_startIndex,$(to_appendLabel+lbl),toWv
		endfor 
	else
		for (i=0;i<num;i+=1)
			lbl=GetDimLabel(fromWv, fromDim, i+from_startIndex)
			if (doReplace)
				lbl=ReplaceString(replaceThisStr,lbl,withThisStr)
			endif
			SetDimLabel toDim,i+to_startIndex,$(lbl+to_appendLabel),toWv
		endfor 
	endif
end

function/s dl_getLblsAsList(fromWvRef,fromDim,from_startIndex,from_endIndex[matchingThisMatchStrListOnly,listItemNum,indsOnly,forceFromWv])
	String fromWvRef
	Variable fromDim,from_startIndex,from_endIndex
	String matchingThisMatchStrListOnly		//returns only those matching one or more match strings in this match str list
	Variable listItemNum						//optionally just save one list item from each lbl, meant for if labels are comma delim lists
	Variable indsOnly
	WAVE forceFromWv		//optionally pass a wave that will supercede fromWvRef, which can be left ""

	Variable used_listItemNum
	if (ParamIsDefault(listItemNum))
		used_listITemNum=0
	else
		used_listITemNum=listItemNum
	endif

	if (ParamIsDefault(forceFromWv))
		WAVE fromWv = $fromWvRef
	else
		WAVE FromWv = forceFromWv
	endif
	
	if (numtype(from_startIndex))
		from_startIndex = 0
	endif
	if (numtype(from_endIndex))
		from_endIndex = dimsize(fromWv,fromDim)-1
	endif
	
	Variable returnIndsOnly=!paramisdefault(indsOnly) && indsOnly
	string out=""
	
	Variable noMatchStringList = ParamIsDefault(matchingThisMatchStrListOnly) || !itemsinlist(matchingThisMatchStrListOnly)
	
	variable i
	
	if (noMatchStringList)
		for (i=from_startIndex;i<=from_endIndex;i+=1)
			if (returnIndsOnly)
				out += num2str(i)+";"
			else
				out += stringfromlist(used_listITemNum,GetDimLabel(fromWv, fromDim, i ))+";"
			endif
		endfor
	else
		String lbl
		for (i=from_startIndex;i<=from_endIndex;i+=1)
			lbl = GetDimLabel(fromWv, fromDim, i )
			if (itemsinlist(text_matchesToListOfMatchStrs(lbl,matchingThisMatchStrListOnly)))
				if (returnIndsOnly)
					out += num2str(i)+";"
				else
					out += stringfromlist(used_listITemNum,lbl) +";"
				endif
			endif
		endfor
	endif
	
	return out
end

function dl_replaceLblSubstring(replaceThisStr,withStr,wv,dim,startIndex,num)
	STring replaceThisStr,withStr
	WAVE wv
	Variable dim,startIndex,num
	
	variable i,ind,indLimit=dimsize(wv,dim); string dl
	for (i=0;i<num;i+=1)
		ind=startIndex+i
		if (ind>=indLimit)
			break
		endif
		dl = getdimlabel(wv,dim,ind)
		dl = replacestring(replaceThisStr,dl,withStr)
		SetDimLabel dim,ind,$dl,wv 
	endfor
end

//for 1 dimensional numeric waves: set a row value and its label
function dl_assignAndLbl(wv,row,val,labelStr)
	WAVE/D wv
	Variable row			//row to be set
	Double val			//value at row
	String labelStr		//dimension label for row
	
	wv[row] = val
	SetDimLabel 0,row,$labelStr,wv
	
	return val
end

//for 1 dimensional text waves: set a row value and its label
function dl_assignAndLbl_T(wv,row,val,labelStr)
	WAVE/T wv
	Variable row			//row to be set
	String val			//value at row
	String labelStr		//dimension label for row
	
	wv[row] = val;SetDimLabel 0,row,$labelStr,wv
end


function dl_appendToLbls(wv,dim,appendStr,appendBeforeLblNotAfter,startIndex,endIndex)
	WAVE wv; String appendStr
	Variable appendBeforeLblNotAfter
	Variable dim
	Variable startIndex	//first position
	Variable endIndex	//lastPosition (inclusive--the label at this position will change if in range of the wave)
	
	if ( (startIndex < 0 ) || numtype(StartIndex))
		startIndex = 0
	endif
	
	Variable dimLen = DimSize(wv,dim)
	
	if ( (endIndex > dimLen - 1) || numtype(endIndex) )
		endIndex = dimLen-1
	endif
	
	variable i; string lbl
	if (appendBeforeLblNotAfter)	
		for (i=startIndex;i<=endIndex;i+=1)
			lbl = appendStr + GetDimLabel(wv, dim, i)
			SetDimLabel dim,i,$lbl,wv	
		endfor
	else
		for (i=startIndex;i<=endIndex;i+=1)
			lbl = GetDimLabel(wv, dim, i) + appendStr
			SetDimLabel dim,i,$lbl,wv	
		endfor	
	endif
	
	return endIndex - startIndex + 1
end


//auto label dimensions by waveName and dim index
function dl_lblByIndAndWvName(wv,dim,preAppendStr)
	WAVE wv; Variable dim		//dim to label, e.g. 0 = rows, 1 = cols
	String preAppendStr		//string to put between wave name and dim index
	
	String labelStr = NameOfWave(wv) + preAppendStr
	
	dl_lblByInd(nameofwave(wv),dim,labelStr,1)
	
end

function dl_lblByInd(ref,dim,appendStr,appendBeforeDimIndexNotAfter,[startPos,num,countFromStartPos,byScaledValue,xValWv])
	String ref; Variable dim		//dim to label, e.g. 0 = rows, 1 = cols
	String appendStr				//string (if any) to append along with num2str(dim index)
	Variable appendBeforeDimIndexNotAfter	//specify whether to append string after (0) or before (1) dim index
	Variable startPos,num
	Variable countFromStartPos		//default is to label by absolute index in wave, pass this as 1 to get count from startPos .. ignored without startPos
	Variable byScaledValue		//optionally pass as 1 to label by scaled value at index (pnt2x / IndexToScale)
	WAVE xValWv		//optionally pass an x wave instead of using automatically computed values. Uses text_str2num so decimals and exponents are OK
	
	Variable doLblByScale = (!ParamIsDefault(byScaledValue) && !byScaledValue) || !paramIsDefault(xValWv)
	
	if (ParamIsDefault(startPos))
		startPos = 0
	endif
	
	Variable numel = dimsize($ref,dim),endPos
	if (ParamIsDefault(num) || ( startPos + num >= numel) )
		endPos = numel - 1
	else
		endPos = startPos + num - 1
	endif
	
	WAVE/Z wv = $ref
	if (!waveexists(wv))
		return 0
	endif
	Variable i,indVal,scaledVal
	Variable labelCountOffset = ( !ParamIsDefault(startPos) && !ParamIsDefault(countFromStartPos) && (numtype(countFromStartPos)==0) ) ? startPos : 0
	String lbl,valStr
	for (i=startPos;i<=endPos;i+=1)
		indVal = i-labelCountOffset
		if (doLblByScale)
			if (paramIsDefault(xValWv))		//values from calculated scaling
				scaledVal = IndexToScale(wv,indVal,dim)
			else		//values from x wv
				scaledVal = xValWv[indVal]
			endif
			valStr = text_num2str(scaledVal)
		else
			valStr = num2str(indVal)
		endif
		lbl = selectstring(appendBeforeDimIndexNotAfter,valStr+appendstr,appendStr+valStr)
		SetDimLabel dim,i,$lbl,wv
	endfor	
end

//return a list of values for dims with label matching lblMatchStr
//only good for rows or columns, not good for 2- or more dimensional
function/S dl_matchingLabelValues(ref,dim,secondDim_index,lblMatchStr,listKeyedListOrIndices)
	String lblMatchStr
	String ref; variable dim		//wave and dimension of labeling. uses ref instead of wave so that text or numeric can be instanteated as appropriate
	variable secondDim_index		//e.g. if dim == 0, get label from each row and return value from rows with matching label at column = secondDim_index
	Variable listKeyedListOrIndices		//0 for a list of the values, 1 for a key-word paired list of each label with its value, 2 for list of matching indices
	
	if (numtype(secondDim_index) == 2)		//NaN
		secondDim_index = 0
	endif
	
	Variable isNumeric = wavetype($ref,1) == 1
	Variable isText = wavetype($ref,1) == 2
	
	String keySepStr = ":", listSepStr = ";"
	
	String out = "", lbl
	Variable i
	if (isNumeric)
		WAVE wv = $ref
		
		if (dim)		//dim > 0 = columns
		
			for (i=0;i<DimSize(wv,1);i+=1)
				lbl = getdimlabel(wv,1,i)	
				if (stringmatch(lbl,lblMatchStr))
					switch (listKeyedListOrIndices)
						case 1:
							out += lbl + keySepStr + num2str(wv[secondDim_index][i]) + listSepStr
							break
						case 0:
							out +=  num2str(wv[secondDim_index][i]) + listSepStr
							break
						case 2:
							out += num2str(i) + listSepStr
							break
					endswitch
				endif	
			endfor
			
		else			//dim == 0 = rows
		
			for (i=0;i<DimSize(wv,0);i+=1)
				lbl = getdimlabel(wv,0,i)	
				if (stringmatch(lbl,lblMatchStr))
					switch (listKeyedListOrIndices)
						case 1:
							out += lbl + keySepStr +  num2str(wv[i][secondDim_index]) + listSepStr
							break
						case 0:
							out +=  num2str(wv[i][secondDim_index]) + listSepStr
							break
						case 2:
							out += num2str(i) + listSepStr
							break
					endswitch
				endif	
			endfor
			
		endif
	
		return out
	endif
	
	if (isText)
		WAVE/t wv_t = $ref
		if (dim)		//dim > 0 = columns
		
			for (i=0;i<DimSize(wv_t,1);i+=1)
				lbl = getdimlabel(wv_t,1,i)	
				if (stringmatch(lbl,lblMatchStr))
					switch (listKeyedListOrIndices)
						case 1:
							out += lbl + keySepStr + wv_t[secondDim_index][i] + listSepStr
							break
						case 0:
							out += wv_t[secondDim_index][i] + listSepStr
							break
						case 2:
							out += num2str(i) + listSepStr
							break
					endswitch
				endif	
			endfor
			
		else			//dim == 0 = rows
		
			for (i=0;i<DimSize(wv_t,0);i+=1)
				lbl = getdimlabel(wv_t,0,i)	
				if (stringmatch(lbl,lblMatchStr))
					switch (listKeyedListOrIndices)
						case 1:
							out += lbl + keySepStr + wv_t[i][secondDim_index] + listSepStr
							break
						case 0:
							out += wv_t[i][secondDim_index] + listSepStr
							break
						case 2:
							out += num2str(i) + listSepStr
							break
					endswitch
				endif	
			endfor
			
		endif
	
		return out	
	
	
	endif
	
end

//quickly switch between comma-separated and semi-colon-separated string lists
function/S sc2c(str,appendTrailingSemiColon)
	String str
	Variable appendTrailingSemiColon
	
	return text_semiColonsToCommas(str,appendTrailingSemiColon)
end

function/S text_semiColonsToCommas(str,appendTrailingSemiColon)
	String str
	Variable appendTrailingSemiColon	//sometimes useful when making a list into a comma list and then adding to another comma list, with lists delimited by semi colons
	
	if (appendTrailingSemiColon)
		return replaceString(";",str,",") + ";"
	endif
		
	return replaceString(";",str,",")
end
function/S c2sc(str)
	String str
	
	return text_commasToSemiColons(str)
end
function/S text_commasToSemiColons(str)
	String str
	
	return replaceString(",",str,";")
end	




function constrain(num,minVal,maxVal)
	Double num,minVal,maxVal
	
	return min(max(num,minVal),maxVal)
end


function numFromList(index,list)
	Variable index;String list
	
	return str2num(stringfromlist(index,list))
end

//return the name of all background tasks
function/s background_getTaskList()
	ctrlnamedbackground _all_,status;
	int i,num = itemsinlist(S_info,"\r"); string currInfo,out=""
	for (i=0;i<num;i++)
		currInfo = stringfromlist(i,s_info,"\r")
		out += stringbykey("name",currInfo)	+";"
	endfor

	return out
end


function wrapIndex(newIndex,numIndices)
	int newIndex,numIndices
	
	if (newIndex >= 0)
		return mod(newIndex,numIndices)
	endif
	
	return mod(mod(newIndex,numIndices)+numIndices,numIndices)		//in case of negative, left-most mod removes negative multiples of numIndices, second one handles case of that outputting numIndices, which needs to be truncated
end

//from https://www.wavemetrics.com/code-snippet/get-free-memory-gb thomas braun
Function GetFreeMemoryInGb()
    variable freeMem

	#if defined(IGOR64)
	    freeMem = NumberByKey("PHYSMEM", IgorInfo(0)) - NumberByKey("USEDPHYSMEM", IgorInfo(0))
	#else
	    freeMem = NumberByKey("FREEMEM", IgorInfo(0))
	#endif

    return freeMem / 1024 / 1024 / 1024
End


//save waves on a graph to file and put graph recreation macro on clipboard (also returns it and prints it to command line)
//macro will automatically map to the file to find the waves and recreate the graph, even in another igor procedure
function/S fio_saveGraphWithWaves(overwritePath, [pathUsed, winN,skipSave,useUserFilesPath,makeRecreationExecutable])
	variable overwritePath
	String winN
	String &pathUsed 	//pass to have this reference filled with the used path
	Variable skipSave		//optionally skip saving and just get the macro string, which is useful if waves are already saved but graphs changed
	Variable useUserFilesPath	//optionally pass to use userFilesPath
	Variable makeRecreationExecutable	//optionally pass to make directly executable; strips recreation macro of function parts
	
	String pathStr = "graphSavePath"

	if (ParamIsDefault(useUserFilesPath) || !useUserFilesPath)
		if (overwritePath)
			NewPath/O/Q $pathStr
		else		//use current graphSavePath, if possible, otherwise have user instantiate that path
			PathInfo $pathStr
			if (!V_flag)
				NewPath/O/Q $pathStr
			endif
		endif	
		
	else
		pathStr = "IgorUserFiles"
	endif
	
	if (ParamIsDefault(winN))
		winN = winname(0,disp_getRecreatableWinSelector())
	endif
	
	string recreationStr =  winrecreation(winN,0)
	
	string wlist = wavelist("*",";","WIN:" + winN)
	
	if (PAramIsDefault(skipSave) || !skipSave)
		fio_saveWavesByName("*",pathStr,1, saveListStr = wList)		//save waves on graph as ibw
	endif
	
	PathInfo $pathStr		//makes sure S_path available for writing full path
	string wLoadStr
	Variable num = itemsinlist(wList)
	if (num < 6)		//after this amount it becomes an unreasonably long single line command
		sprintf wLoadStr, "\tfio_loadfiles(\"*\",\".ibw\",loadWvListStr=\"%s\",fullPathStr=\"%s\")\r", wList, S_path 
	else
		wLoadStr="\tString loadWvListStr=\"\"\r"
		Variable i; string temp
		for (i=0;i<num;i+=1)
			wLoadStr+="\tloadWvListStr+=\""+stringfromlist(i,wList)+";\"\r"
		endfor
	
		sprintf temp,"\tfio_loadfiles(\"*\",\".ibw\",loadWvListStr=loadWvListStr,fullPathStr=\"%s\")\r",S_path
		wLoadStr+=temp
	endif
		
	Variable firstLinePnts = strsearch(recreationStr, "\r", 1)
	String firstLine = recreationStr[0,firstLinePnts]
	String functionCmd=stringfromlist(1,firstLine," ")
	
	recreationStr = firstLine + wLoadStr + recreationStr[firstLinePnts,inf] + " //"+functionCmd +"<--run this"
	
	If (!ParamIsDefault(makeRecreationExecutable) && makeRecreationExecutable)
		recreationStr = removelistitem(0,recreationStr,"\r")
		String pauseUpdates = listmatch(recreationStr,"*PauseUpdate*","\r"),line
		Variable numMatch=itemsinlist(pauseUpdates),j
		for (j=0;j<numMatch;j+=1)
			line=stringfromlist(j,pauseUpdates,"\r")
			recreationStr = removefromlist(line,recreationStr,"\r")
		endfor
		recreationStr = ReplaceString("Display",recreationStr,"Display/N="+winN,1,1)
		Variable len = itemsinlist(recreationStr,"\r")
		recreationStr = removelistitem(len-1,recreationStr,"\r")
		recreationStr = removelistitem(len-2,recreationStr,"\r")
	endif
	
	putscraptext recreationStr		//copy recreation macro text to clipboard
	
	if (!ParamIsDefault(pathUsed))
		pathUSed = pathStr
	endif
	
	return recreationStr
end


function/S fio_saveWavesByName(matchStrOrWvList, pathName, appendSavePath, [saveListStr, out_saveListStr, out_saveCount,deleteAfterSave])
	String matchStrOrWvList
	String pathName		//if blank, prompts user
	String saveListStr	//pass to save specific waves by name. matchStr must still apply and can just be "*" to save all these waves
	String &out_saveListStr	//optionally pass string (by ref) to get list of waves that were saved. saved list is APPENDED to out_saveListStr, unless out_saveListStr is empty or zero length
	Variable appendSavePath	//pass to append full path for save to wave note (useful if you know other related waves were saved in the same place/time and then can be found)
	Variable &out_saveCount	//pass variable into which successful save count is returned
	Variable deleteAfterSave	//pass true to delete waves from experiment after a successful save
	
	if (strlen(pathName) == 0)
		pathName = "saveMatchingWavesPath"
		NewPath/O/Z $pathName
		
		if (V_flag)
			Print "fio_saveWavesByName aborted. Failed to create path with pathName = " + pathName
		endif
	endif
	
	PathInfo $pathName
	if (!V_flag)
		Print "Resetting path in fio_saveWavesByName()..."
		NewPath/O/Z $pathName
	endif
	String full_path = S_path
	
	if (strlen(matchStrOrWvList) == 0)
		matchStrOrWvList = "*"
	endif

	String list		//load list
	if (StringMatch(matchStrOrWvList, "*;*"))		//if has semi-colon, assume wave list
		list = matchStrOrWvList
	else
		list = wavelist(matchStrOrWvList, ";","")	//String excelWavesList = wavelist("excel_*", ";","")
										//wavelist also pre-selects for waves that exist, so no need to check the reference 
	endif
	list = RemoveFromList("",list)	//avoid ";;;;" reps								
										
										
	Variable i, errorCode
	String currRef, savedList = "", killedList=""
	Variable out_saveCount_temp = 0		//attempts to count succesful saves, but may not be accurate depending on the states thrown by save call
	for (i=0;i<ItemsInList(list);i+=1)
		currRef = StringFromList(i, list)
		//if additional saveListStr passed, check that this wave is present there and skip if not
		if (!ParamIsDefault(saveListStr))
			if (WhichListItem(currRef, saveListStr) == -1)
				continue		//if saveListStr is passed and the current wave is not in the list, skip it
			endif
		endif
		
		//check that wave exists; if not, let user know and skip
		if (!strlen(currRef))
			continue	//dont bother alerting for this case, likely just an extra ";"
		endif
		if ( !WaveExists($currRef) )
			Print "fio_saveWavesByName(): failed to save waveRef=", currRef, ". Wave does not exist. Wave skipped."
			continue
		endif
		
		//append save path if requested
		if (appendSavePath)
			Note/nocr $currRef, "fio_savePath:" + full_path + ";"
		endif

		//save the wave
		SAVE/C/O/P=$pathName $currRef
		
		//report errors
		errorCode = GetRTError(1)		//clears any RT error, but this error should be specific to save
		if (errorCode)
			Print "Error in fio_saveWavesByName, likely while saving wave = " + StringFromList(i, list) + ". Error msg = " + GetErrMessage(errorCode)
		else
			out_saveCount_temp += 1
			if (deleteAfterSave)
				killwaves/z $currRef
				killedList += currRef + ";"
			endif
		endif
		
		savedList += currRef + ";"
	endfor
	
	if (!ParamIsDefault(out_saveListStr))
		if (strlen(out_saveListStr) == NaN)
			out_saveListStr = savedList
		else
			out_saveListStr += savedList
		endif
	endif
	
	if (!ParamIsDefault(out_saveCount))
		out_saveCount = out_saveCount_temp
	endif	
	if (itemsinlist(killedList) > 0)
		Print "fio_saveWavesByName(): killed waves after seemingly successful save:",killedList
	endif
	return pathName
end	//fio_saveWavesByName

Function/S fio_loadfiles(matchStr,extensionStr,[pathName,loadWvListStr,doNotloadWvListStr,out_fileListStr,out_waveListStr,out_fullPathsListStr,out_extensionsListStr,fullPathStr,unloadEachNewWave,out_usedExtensionStr,skipPreExisting])//,smartSyncHandling])
	String extensionStr					//file type identifier: e.g. ".ibw" for igor binary, or ".txt", or ".abf. At present, if empty string, set to ".ibw"
	String matchStr 					// File name matching, e.g. *150917*. extension string is used in matching; if not included, its added
	
	String pathName		// Name of an Igor symbolic path or "" or default to get a dialog
	String loadWvListStr	//optionally pass to load specific waves
	String doNotloadWvListStr		//optionally pass to skip loading specific waves
	String &out_fileListStr		//optionally pass to have list of FILES actually loaded (including those skipped with skip load) returned in this variable
	String &out_waveListStr		//optionally pass to have list of WAVES actually loaded (including those skipped with skip load) returned in this variable
	String &out_fullPathsListStr, &out_extensionsListStr		//same for paths and extensions..wave by wave list
	String &out_usedExtensionStr	//optionally pass to have extension of files loaded set in this variable
	String fullPathStr	//pass a complete path (e.g. for bringing back waves into a different file where the same path under the same name may not exist
	Variable unloadEachNewWave	//pass true to do everything but actually load wave -- helpful for mapping
	Variable skipPreExisting	//optionally pass to skip waves that already exist in this instance of igor
//	Variable smartSyncHandling	//pass as 1 to attempt to trigger smart sync download of the file before loading (loadWave does not)
		
	if (strlen(matchStr) == 0)
		matchStr = "*"
	endif
		
	if (strlen(extensionStr) == 0)
		extensionStr = ".ibw"			//igor binary wave is default. This would have to be modified to load a wave without an extension
	endif
		
	if (!ParamIsDefault(loadWvListStr) && strlen(loadWvListStr) )
		loadWvListStr = text_appendStrIfAbsent(loadWvListStr,";",0)
		loadWvListStr = replacestring(";",loadWvListStr,".ibw;")		//will look for matches to file names not wave names
	endif
	if (!ParamIsDefault(doNotloadWvListStr) && strlen(doNotloadWvListStr) )
		doNotloadWvListStr = text_appendStrIfAbsent(doNotloadWvListStr,";",0)
		doNotloadWvListStr = replacestring(";",doNotloadWvListStr,".ibw;")		//will look for matches to file names not wave names
	endif
			
	if (!ParamIsDefault(fullPathStr))		//fullPathStr passed == used if so
		pathName = "LoadIndexedFilePath"
		NewPath/Q/O $pathName, fullPathStr
	elseif (ParamIsDefault(pathName) || (strlen(pathName) == 0))
		NewPath/Q/O/M="Choose a folder containing data files" LoadIndexedFilePath
		if (V_flag != 0)
			return "" //User cancelled				
		endif
		pathName = "LoadIndexedFilePath"
	else		//pathName passed
		PathInfo $pathName
		if (!V_flag)		//no path exists, so prompt user; otherwise use this pathName
			Print "fio_loadFiles(): pathName,", pathName, "passed but could not be found. Prompting user to choose path"
			NewPath/Q/O/M="Choose a folder containing data files" $pathName
			if (V_flag != 0)
				return "" //User cancelled				
			endif 
		endif
	endif

	string filesLoadedList = "",filesLoadedExtensionList = "", wavesLoadedList = "", filePathsList = "" 		//tracks files actually loaded
	variable numFilesLoaded = 0
 	String fileNames = IndexedFile($pathName, -1, extensionStr)	//-1 leads to returning all of them, semi-colon delimited list

 	String completeMatchStr
 	if (stringmatch(matchStr, "*" + extensionStr))	//matchstring already has extension string
 		completeMatchStr = matchStr
 	else
 		completeMatchStr = matchStr + extensionStr
 	endif
 	String matchingFileNames = ListMatch(fileNames, completeMatchStr, ";")		//makes list of just matches
 	//iterate through matchingFileNames, and load those waves
 	Variable i, currIndex,j,refNum; String currFileName		//j used to add extra waves to list
	for (i=0;i<ItemsInList(matchingFileNames,";");i+=1)
		currFileName = StringFromList(i,matchingFileNames,";")
		if (!ParamIsDefault(loadWvListStr))
			if (WhichListItem(currFileName, loadWvListStr) == -1)		//if not in list, skip load
				continue
			endif
		endif
		if (!ParamIsDefault(doNotloadWvListStr))
			if (WhichListItem(currFileName, doNotloadWvListStr) > -1)
				continue
			endif
		endif

		killvariables/Z V_flag		//so that no matter what this is reset by loadwave
		if (!ParamIsDefault(skipPreExisting) && skipPreExisting)
			if (waveExists($ReplaceString(extensionStr,currFileName,"")))
				continue
			endif
		endif
		
//		if (!paramIsDefault(smartSyncHandling) && smartSyncHAndling)
//			open/r/p=$home refNum as currFileName
//			close refNum
//		endif
//		
		LoadWave/H/Q/W/O/P=$pathName currFileName	
		numFilesLoaded += V_flag
		wavesLoadedList += s_waveNames		//waves loaded; this is semi-colon delimited'
		for (j=0;j<V_flag;j+=1)		//make sure that there's a file full path and a file name with extension for each wave
			filePathsList += S_path + ";"				//file full path
			filesLoadedList += s_fileName + ";"		//file name with extension
			filesLoadedExtensionList += StringFromList(1,s_fileName, ".") + ";"		//loaded extension only
		endfor
		if (!ParamIsDefault(unloadEachNewWave) && unloadEachNewWave)
			killWavesByName(s_wavenames)
		endif
	endfor

	if (!ParamIsDefault(out_fileListStr))		//currently no checking to see that waves were saved successfully, believe this would need getRTError or whatever
		if (numtype(strlen(out_fileListStr)))
			out_fileListStr = filesLoadedList
		else
			out_fileListStr += filesLoadedList
		endif
	endif	

	if (!ParamIsDefault(out_waveListStr))		//currently no checking to see that waves were saved successfully, believe this would need getRTError or whatever
		if (numtype(strlen(out_waveListStr)))
			out_waveListStr = wavesLoadedList
		else
			out_waveListStr += wavesLoadedList
		endif
	endif	

	if (!ParamIsDefault(out_fullPathsListStr))		//currently no checking to see that waves were saved successfully, believe this would need getRTError or whatever
		if (numtype(strlen(out_fullPathsListStr)))	
			out_fullPathsListStr = filePathsList
		else
			out_fullPathsListStr += filePathsList
		endif
	endif	

	if (!ParamIsDefault(out_extensionsListStr))		//currently no checking to see that waves were saved successfully, believe this would need getRTError or whatever
		if (numtype(strlen(out_extensionsListStr)))
			out_extensionsListStr = filesLoadedExtensionList
		else
			out_extensionsListStr += filesLoadedExtensionList
		endif
	endif	

	if (!ParamIsDefault(out_usedExtensionStr))
		out_usedExtensionStr= extensionStr
	endif

	return pathName
end

function/S text_appendStrIfAbsent(str,appendStr,appendToZeroLenStr)
	String str,appendStr
	Variable appendToZeroLenStr	//pass true to append to zero length strings, otherwise zero length strings are returned unchanged
	
	Variable len_appStr = strlen(appendStr)
	Variable len_str = strlen(str)
	
	//if !appendToZeroLenStr, check str len and return string if no change needed (len_str < 1)
	if (!appendToZeroLenStr && (len_str < 1))
		return str
	endif
	
	//add append str if appendStr does not already terminate str
	if (!stringmatch(str[len_str-len_appStr,inf],appendStr))
		str += appendStr
	endif
	
	return str

end

function killWavesByName(matchStrOrListOf, [reportFailure, out_killedOrNeverExistedList,userPromptedWindowKilling,savePathName])
	String matchStrOrListOf; Variable reportFailure
	String &out_killedOrNeverExistedList	//pass to get list of waves that were in list and no longer exist after attempted kill
	Variable userPromptedWindowKilling		//optionally pass for user prompted killing of windows that contain a wave and thus stop its killing. 1 to kill with prompt.2 to kill wihout prompt (use caution)
	String savePathName		//optionally pass the name of a path to a folder to store them in before killing. This can help with memory management. Created if it does not exist
	
	Variable listOnlySuccessfullyKilledWvs = 0		//1 to list just those waves that had existed and were killed, 0 to list all waves that were in list and are no longer present
	
	//deal with potential input of wave list
	int i; String killList=""
	for (i=0;i<ItemsInList(matchStrOrListOf);i+=1)		//works fine if input is single matchStr too
		killList += WaveList(StringFromList(i,matchStrOrListOf),";","")
	endfor
	
	Variable doSave = !ParamIsDefault(savePathName) && (strlen(savePathName) > 0)
	if (doSave)
		pathinfo $savePathName
		if (!V_flag)
			newpath/o/q/z/m="KillWavesByName(): Choose a folder to store waves saved before killing" $savePathName
		endif
		pathinfo $savePathName
		if (!V_flag)		//failed
			print "KillWavesByName() savePathName for saving before wave kill is invalid and was not set by user. aborting."
			return 0
		endif
	endif
	
	String currRef; variable count = 0, waveExisted, waveExistsAfterKill
	String killedOrNeverExistedList = "", successList = "", failList = ""
	int num = itemsinlist(killList)
	for (i=0;i<num;i+=1)
		currRef = StringFromList(i,killList)
		if (doSave)
			save/c/o/p=$savePathName $currRef
		endif
		waveExisted = WaveExists($currRef)
		KillWaves/Z $currRef; count += 1
		waveExistsAfterKill = WaveExists($currRef)
		
		if (waveExistsAfterKill)
			if (!ParamIsDefault(userPromptedWindowKilling) && userPromptedWindowKilling)
				if (userPromptedWindowKilling != 2)
					disp_killWinsWithWave(currRef,1,1)	//kill w/prompt
				else
					disp_killWinsWithWave(currRef,0,1)	//kill w/o prompt
				endif
				doupdate
				waveExistsAfterKill = WaveExists($currRef)
				if (waveExistsAfterKill)
					failList += currRef + ";"
				else
					killedOrNeverExistedList += currRef + ";"
					if (waveExisted)
						successList += currRef + ";"
					endif
				endif
			else
				failList += currRef + ";"
			endif
		else
			killedOrNeverExistedList += currRef + ";"
			if (waveExisted)
				successList += currRef + ";"
			endif
		endif
		
		if (!ParamIsDefault(reportFailure))
			if (waveExistsAfterKill)
				Print "In killWavesByName(matchStr), failed to kill wave = " + currRef
			endif
		endif
	endfor
	
	if (!paramIsDefault(out_killedOrNeverExistedList))
		out_killedOrNeverExistedList = killedOrNeverExistedList
	endif
	
	return itemsInList(killedOrNeverExistedLisT)
end

//kill any windows containing a wave, optionally checking with user before each windowkill call. 
//returns list of those waves that either could not be killed or were cancelled by user
//if window containing wave still present after call to this function, then
// strlen(disp_killWinsWithWave()) > 0 will be true
function/S disp_killWinsWithWave(wvMatchStr,promptUserBeforeKill,killMatchingWvsAfter)
	String wvMatchStr		//match string for waves to kill
	Variable promptUserBeforeKill		//pass to bring each window to top then prompt to check with user if kill ok
	Variable killMatchingWvsAfter		//attempts to kill matching waves after killing all windows

	Variable userPromptDefault = 1		//1 for poised to kill window, 0 for not

	String listOfWinsWithWv = disp_getWinListForWv(wvMatchStr)
//	Print "listOfWinsWithWv",listOfWinsWithWv
	String win, killFails="", killCancels="", killSuccesses=""
	variable i
	if (promptUserBeforeKill)
		Variable reallyKillWindow		//variable to prompt
		for (i=0;i<ItemsInList(listOfWinsWithWv);i+=1)
			win = stringfromlist(i,listOfWinsWithWv)
			setWindowPos_center(win, 1)	
			reallyKillWindow = userPromptDefault		
			prompt reallyKillWindow, "Really kill window="+win+ "? [1: yes. 0: no.]"
			doprompt "disp_killWinsWithWave()", reallyKillWindow
			if (reallyKillWindow)
				killwindow/Z $win
				if (Wintype(win))
					killFails += win + ";"
				else
					killSuccesses += win + ";"
				endif
			else
				killCancels += win + ";"
			endif
		endfor
	else
		for (i=0;i<ItemsInList(listOfWinsWithWv);i+=1)
			win = stringfromlist(i,listOfWinsWithWv)
			killwindow/Z $win
			if (Wintype(win))
				killFails += win + ";"
			else
				killSuccesses += win + ";"
			endif
		endfor
	endif	
	
	if (killMatchingWvsAfter)
		killWavesByName(wvMatchStr)
	endif
	
	return killFails + killCancels
end

function/S disp_getWinListForWv(wvMatchStrOrList[forceWinTypes])	
	String wvMatchStrOrList	//match string for waves to list
	Variable forceWinTypes		//optionally pass an input for winList wintypes, otherwise will list tables and graphs
									//pass forceWinTypes=1 for graphs only forceWinTypes=2 for tables only, etc
	
	Variable windowTypes = ParamIsDefault(forceWinTypes) ? 2^0 + 2^1 : forceWinTypes
	//includes graphs, tables (I don't think any other can contain waves in a way that stops
	//the wave from being killed, which is my main goal with this type of function
	//skips layouts, notebooks, panels, procedures, etc.
	
	
	String all_wins = winList("*",";","WIN:"+num2str(windowTypes))
	Variable i,j; string matchStr, win, winWvList, out = ""
	
	for (i=0;i<itemsinlist(wvMatchStrOrList);i+=1)
		matchStr = stringfromlist(i,wvMatchStrOrList)
		
		for (j=0;j<itemsinlist(all_wins);j+=1)
			
			win = stringfromlist(j,all_wins)
			
			winWvList = wavelist(matchStr,";","WIN:"+win)		//waves in curr window matching wvMatchStrOrList
			if (ItemsInLisT(winWvList) > 0)
				out += win + ";"
			endif	
		
		
		endfor
	
	endfor
	
	return out	
end

//center a window and optionally bring it to the top
function setWindowPos_center(winN, bringToTop)
	String winN
	Variable bringToTop
	
	if (!strlen(winN))
		winN = winname(0,1)
	endif
	
	Variable left_center=250, top_center=200//where to set left and and top of window, size unchanged. 250,200 is good for my computer
	Variable left_to_right, top_to_bottom	
	Variable left_original,top_original,right_original,bottom_original	//tracks original window pos
	
	getWindowPos(left_original,top_original,right_original,bottom_original,winN=winN)
	
	left_to_right = right_original - left_original
	top_to_bottom = bottom_original-top_original
	setWindowPos(left_center,top_center,left_center+left_to_right,top_center+top_to_bottom,winN=winN)
	
	if (bringToTop)
		dowindow/F $winN
	endif
end

function getWindowPos(left, top, right, bottom, [winN])
	Variable &left, &top, &right, &bottom; String winN
	
	if (ParamIsDefault(winN))
		winN = ""
	endif
	
	GetWindow $winN, wsize
	left =V_left
	right =V_right
	top =V_top
	bottom= V_bottom
end

function setWindowPos(left, top, right, bottom, [winN])
	Variable left, top, right, bottom; String winN
	
	if (ParamIsDefault(winN))
		winN = ""
	endif
	
	MoveWindow/W=$winN left, top, right, bottom
end


//procs for quickly copying waves between instances of Igor
//this is useful when sharing data with a collaborator, for whom
//all the analysis in the original pxp could be confusing
//*currently, this ipf file is required in both instances of Igor involved in the transfer
//in future, could extend to other window types and consider some sort of package file
//that contains the waves (and strings, variables, etc) and recreation commands necessary
//to reproduce the window(s) in any other instance of igor

//Note: this currently includes some unnecessarily complex helper functions that should probably go in a different ipf
//And the code could probably be more concise and efficient..


//copies necessary information for graph recreation to clipboard
//and saves the waves to the hard drive (in a location that must be accessible to the other Igor instance)
//(that limits it to the same computer or another computer with extremely similar file structure due to something like Dropbox sync)
Menu "Windows"
	"Copy Waves+Disp command/8",/Q,fio_saveGraphWithWaves(0,useUserFilesPath=1,makeRecreationExecutable=1)
End

//run the clipboard text (i.e., in another Igor instance), which loads the saved waves and recreates the windows
Menu "Windows"
	"Paste Graph Waves & Disp command/9",/Q,executeWavesAndGraphFromClip()
end

//another way to save the graph and its waves
Menu "GraphPopup"
	"Copy Graph Waves & Disp command",/Q,fio_saveGraphWithWaves(0,useUserFilesPath=1,makeRecreationExecutable=1)
end

//for use in a second igor pxp: this runs the commands on the clipboard, which includes loading saved waves and recreating the window
//eventually make this save waves to a subfolder in the user files and add a hook to delete it on program close
function executeWavesAndGraphFromClip()
	String clip=getscraptext(),line,strname
	VAriable i,lines=itemsinlist(clip,"\r")
	for (i=0;i<lines;i+=1)
		line=stringfromlist(i,clip,"\r")
		if (stringmatch(line,"*String loadWvListStr*"))
			SVAR/Z loadWvListStr
			if (SVAR_exists(loadWvListStr))
				line = replacestring("String ",line,"",0,1)
			endif
		endif
		execute/Q line
	endfor
end

function disp_getRecreatableWinSelector()
	return 2^0 + 2^1 + 2^2 + 2^6	//graphs,tables,layouts,panels .. maybe others are covered? not sure haven't tried
end 

function/S win_getUserData(winN, userDataStr)
	String winN, userDataStr
	
	if (strlen(winN) < 1)
		winN = winname(0,16)		//top notebook by default
	endif
	
	return GetUserData(winN, "", userDataStr )
end


//from http://www.igorexchange.com/node/1275 aclight 12/7/09, modified slightly
Function year()
	return str2num(StringFromList(0, Secs2Date(DateTime, -2), "-"))
End
 
Function month()
	return str2num(StringFromList(1, Secs2Date(DateTime, -2), "-"))
End
 
Function day()
	return str2num(StringFromList(2, Secs2Date(DateTime, -2), "-"))
End
 
Function hour()
	return str2num(StringFromList(0, Secs2Time(DateTime, 3), ":"))
End
 
Function minute()
	return str2num(StringFromList(1, Secs2Time(DateTime, 3), ":"))
End
 
Function second()
	return str2num(StringFromList(2, Secs2Time(DateTime, 3), ":"))
End

Function/S GetDateTimeString()
	String dateTimeString = ""
	sprintf dateTimeString, "%.4d%.2d%.2d %.2d:%.2d:%.2d", year(), month(), day(), hour(), minute(), second()
	return dateTimeString
End

//returns the axis-relative location of the mouse cursor
function disp_getMouseLoc(s,axNameStr)
	STRUCT WMWinHookStruct &s
	String axNameStr		//name of axis of interest
	
	string axInfo=AxisInfo(s.winName, axNameStr)
	String axisType = StringByKey("AXTYPE", axInfo)
	
	//determine if vertical, return y position if so, x position if not
	Variable isVert = stringmatch(axisType, "left") || stringmatch(axisType, "right")	

	if (isVert)
		return AxisValFromPixel(s.winName, axNameStr, s.mouseLoc.v )
	else
		return AxisValFromPixel(s.winName, axNameStr, s.mouseLoc.h )
	endif
end

//wrapper functions for extracting values from wave references
function getWaveV_val_2D(waveRef, row, col)
	String waveRef; Variable row, col
	
	WAVE/z temp = $waveRef
	if (!waveexists(temp))
		return nan
	endif
	return temp[row][col]
end

function getWaveV_val_1D(waveRef,row)
	String waveRef; Variable row
	
	WAVE/z temp = $waveRef
	if (!waveexists(temp))
		return nan
	endif
	return temp[row]
end


//returns list of matching waves then matching traces, each list semicolon delimited, colon between the two lists. use StringFromList(0, listOut, ":") to get wave names, and StringFromList(1, listOut, ":") for trace names
function/S disp_getMatchingWvsAndTNsList(winN, matchStr, matchToTN_notToWvName)
	String winN, matchStr
	Variable matchToTN_notToWvName	//0 for matches to wave name regardless of each trace name, 1 for matches to each trace name regardless of wave name
	
	if (strlen(matchStr) == 0)
		matchStr = "*"
	endif

	String listOfTraces = TraceNameList(winN, ";", 1)
	String listOfMatchingTraces="", listOfMatchingWaves=""		//list of traces and their associated wave (paired by order) 
	Variable i
	if (matchToTN_notToWvName)
		listOfMatchingTraces = ListMatch(listOfTraces, matchStr)
		listOfMatchingWaves =  text_getWvListFromTraceList(winN, listOfMatchingTraces)		//preserves order of trace list
	else		//match to wave names not trace names
		//check the name of the wave for each trace for a match. if a match, store the trace to be adjusted along with the wave for that trace. must include duplicates because each trace is unique, even if its underlying wave is not
		String listOfWavesForAllTraces = text_getWvListFromTraceList(winN, listOfTraces), currWvRef
		for (i=0;i<ItemsInList(listOfWavesForAllTraces);i+=1)
			currWvRef = StringFromList(i,listOfWavesForAllTraces)
			if (stringmatch(currWvRef, matchStr))
				listOfMatchingWaves += currWvRef + ";"
				listOfMatchingTraces += StringFromList(i, listOfTraces) + ";"
			endif
		endfor
	endif
	
	return listOfMatchingWaves + ":" + listOfMatchingTraces
end

function/S text_getWvListFromTraceList(winN, traceNames)
	String winN, traceNames
	
	String out = "", currTraceName
	Variable i
	for (i=0;i<ItemsInList(traceNames);i+=1)
		currTraceName = StringFromList(i, traceNames)
		out += NameOfWave(TraceNameToWaveRef(winN, currTraceName)) + ";"	
	endfor

	return out
end

function table_clear(tName)
	string tName
	
	if (strlen(tName) < 1)
		tName = winname(0,2)		//top table
	endif
	
	if (wintype(tName) != 2)	// not a table
		Print "In table_clear(), attempt to clear non-table (aborted)"
		return 0
	endif
	
	String tWaves = table_getTableWaves(tName)
	
	Variable i
	for (i=0;i<ItemsInList(tWaves);i+=1)
		RemoveFromTable/W=$tName $StringFromList(i, tWaves)
	endfor
end


//list of waves on a table -- other simpler methods exist
function/S table_getTableWaves(tName)
	String tName

	if (wintype(tName) != 2)	// not a table
		Print "In vis_getTableWaves(), a non-table was passed, function aborted"
		return ""
	endif
	
	String info = tableInfo(tName, -2)
	
	Variable numCols = str2num(StringByKey("COLUMNS", info))
	
	Variable i; String list ="", colWave
	for (i=0;i<numCols;i+=1)
		colWave = table_getTableWave(tName, i)
		if ( (strlen(colWave) > 0) && WaveExists($colWave) && (WhichListItem(colWave, list) < 0) )
			list += colWave + ";"
		endif
	endfor
	
	return list
end

function/S table_getTableWave(tName, tCol)		//returns name of wave in table column tCol
	String tName; Variable tCol

	if (wintype(tName) != 2)	// not a table
		Print "In getTableWave(), a non-table was passed, function aborted"
		return ""
	endif
	if (tCol < -1)
		return ""
	endif
	String info = tableInfo(tName, tCol)
	
	return StringByKey("WAVE", info)
	
end


function df_makeFolder(df_pathStr, setToLevel)
	String df_pathStr		//string of data folder hierarchy
	Variable setToLevel	//-1 to return to current position, 0 or higher for each position in df_pathStr
	
	String dfSav= GetDataFolder(1)		//store current data folder, return to here after executing function

	Variable i,numLevels = ItemsInList(df_pathStr,":")
	String df, dfs = ""
	for (i=0;i<numLevels;i+=1)
		df = StringFromLisT(i,df_pathStr,":")
		if (Stringmatch(df, "root"))		//root folder always exists, go to it if requested
			SetDataFolder root:
		else		//enter folder, creating it if it does not exist
			if (DataFolderExists(df))
				SetDataFolder $df
			else
				NewDataFolder/O/S $df
			endif
		endif
		
		if (i==setToLevel)
			dfSav= GetDataFolder(1)	//store position of data folder for requested level
		endif
	endfor
	
	if (setToLevel < numLevels)	//change to level other than last level if needed
		SetDataFolder dfSav
	endif
	
end


//list matches to a list of matchStrs (extends stringmatch(...) to a list of input matchStrs)
function/S text_matchesToListOfMatchStrs(list,listOfMatchStrs)
	String list		//list to get matching subset from
	String listOfMatchStrs		//match strings
	
	Variable i, num = itemsinlist(list)
	String checked="",matches="",str
	for (i=0;i<num;i+=1)
		str=stringfromlist(i,list)
		if ( WhichListItem(str,checked) < 0)		//not checked
			checked+=str+";"
			
			if (text_matchToListOfMatchStrs(str,listOfMatchStrs))
				matches+=str+";"
			endif
		endif
	endfor
	
	return matches
end

function text_matchToListOfMatchStrs(str,listOfMatchStrs)
	String str,listOfMatchStrs
	
	Variable i,num=itemsinlist(listOfMatchStrs)
	string out="",matchStr
	for (i=0;i<num;i+=1)
		matchStr=stringfromlist(i,listOfMatchStrs)
		if (stringmatch(str,matchStr))
			return 1
		endif
	endfor

	return 0
end

//robustly convert to str names that can be used as wave names / dim labels (. + / - converted to p,a,m)
//use text_str2num to convert back
function/s text_num2str(num)
	Double num
	
	String str = replacestring(".",num2str(num),"p")
	str= replacestring("+",str,"a")
	str= replacestring("-",str,"m")
	
	return str
end

function text_str2num(str)
	String str
	
	if (stringmatch(str,"NaN"))
		return NaN
	endif
	if (stringmatch(str,"inf"))
		return inf
	endif
	if (stringmatch(str,"-inf"))
		return -inf
	endif
	
	str=replacestring("p",str,".")
	str=replacestring("a",str,"+")
	str=replacestring("m",str,"-")
	str=replacestring("n",str,"-")
	
	return str2num(str)
end

function/S getDateStr(igorDate)
	String igorDate	//pass "" for current (computer) date, pass another date otherwise. Format must be as returned by date()
	
	if (strlen(igorDate) < 1)
		igorDate = date()
	endif
	
	String monthsList = "jan;feb;mar;apr;may;jun;jul;aug;sep;oct;nov;dec;"
	make/o/t/n=(12) monthsStrs = selectstring(p < 9, "", "0") + num2str(p+1)
	String expr="([[:alpha:]]+), ([[:alpha:]]+) ([[:digit:]]+), ([[:digit:]]+)"
	String dayOfWeek, monthName, dayNumStr, yearStr
	SplitString/E=(expr) igorDate, dayOfWeek, monthName, dayNumStr, yearStr
	return yearStr[2,inf] + monthsStrs[whichlistitem(monthName,monthsList,";",0,0)] + dayNumStr
	
end