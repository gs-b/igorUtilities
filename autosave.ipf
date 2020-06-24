#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#pragma IndependentModule = AutosaveModule			//allows these functions to run while procedures are uncompiled 

//EXPERIMENT AUTO SAVE FUNCTIONS
//default is that auto save begins on experiment start (assuming code compiles at experiment start)
//otherwise toggle start/stop in the file menu
//if the functions attempt an auto save before a pxp has been saved (and thus has no name)
//then the name begins with ks_autoSaveBaseName followed by the year,month,day,hour,minute,second of the first save (underscore-delimited)

//constants that determine key aspects of auto save behavior -- user should adjust as preferred
static constant k_experimentAutoSaveRate_inMinutes = 10
static constant k_autoSaveCancelWindows_inSeconds = 20
static strconstant ks_autoSaveBaseName = "experimentAutoSave_"

//menu toggle
Menu "File", hideable,dynamic
	selectstring(getExperimentAutoSaveStatus(),"Toggle experiment auto save from off to ON","! Toggle experiment auto save from on to OFF"),/Q,experimentAutoSave("")
end

//start auto save on experiment start
function IgorStartOrNewHook(igorApplicationNameStr)
	String igorApplicationNameStr		//not used
	
	experimentAutoSave("on")	//this line should be added to IgorStartOrNewHook() if another exists already
end

//functions for auto save
function experimentAutoSave(onOrOffStr)
	String onOrOffStr		//"" to toggle, "on" to start, "off" to stop (any other string also defaults to "off")
	
	if (strlen(onOrOffStr) < 1)	//toggle for ""
		onOrOffStr = selectstring(getExperimentAutoSaveStatus(),"on","off")
	endif
	
	strswitch (onOrOffStr)
		case "on":
			//one issue: when Ctrlnamedbackground runs, except apparently at start up, it attempts to auto save immediately when I think due to start=periodTicks it should wait until a full period has passed...
			Variable periodTicks = k_experimentAutoSaveRate_inMinutes*60*60		//convert to ticks (60 per second)
			Ctrlnamedbackground pxpSaveMainBgTask,dialogsOK=0,period=periodTicks,start=periodTicks,proc=pxpSaveMainBg		//set it to start after one period and not to run during dialogs
			print "experiment auto saves started at a rate of every",k_experimentAutoSaveRate_inMinutes,"minutes (adjust with k_experimentAutoSaveRate_inMinutes)"
			break
		default:
			killwindow/z pxpSavePanel
			ctrlnamedbackground pxpSaveHelperBgTask,kill=1	//kill the helper background task (which might or might not exist at a given run time)
			Ctrlnamedbackground pxpSaveMainBgTask,kill=1		//kill the main background task
	endswitch
end	

//returns 1 if auto save is on, 0 if off
function getExperimentAutoSaveStatus()
	Ctrlnamedbackground pxpSaveMainBgTask,status  //if the main background task is running, auto save is ON
	return str2num(stringbykey("RUN",S_info))		//run is 1 if running, in which case auto save is also running
end

function pxpSaveMainBg(s)
	STRUCT WMBackgroundStruct &s
	//check if the experiment has been modified since last save and therefore needs saving
	experimentmodified
	if (!V_flag)
		return 0	//dont try to save at present but continue the background task
	endif
	
	//if there's already an auto save panel up, somehow an auto save is already scheduled to occur (might happen if k_experimentAutoSaveRate_inMinutes is really short relative to k_autoSaveCancelWindows_inSeconds 
	if (wintype("pxpSavePanel") != 0)	
		return 0		//dont try to save at present but continue the background task
	endif
	
	newpanel/n=pxpSavePanel/w=(0,0,200,50)/k=1 as "Auto save experiment"	
	setwindow pxpSavePanel userdata(cancelCountdown)=num2str(k_autoSaveCancelWindows_inSeconds)
	Button cancelAutoSavePxp win=pxpSavePanel,fsize=15,fstyle=1,pos={20,2.5},size={170,40},title="CANCEL pxp auto save",proc=cancelAutoSavePxpBtn
	Ctrlnamedbackground pxpSaveHelperBgTask,period=60,start=60,dialogsOK=0,proc=pxpSaveHelperBg //start helper function running every 60 ticks (~1 second) and starting after 60 ticks
	
	return 0 		//continue the background task
end

function pxpSaveHelperBg(s)
	STRUCT WMBackgroundStruct &s
	
	//cancel if the window has been killed and cancel if so
	if (wintype("pxpSavePanel") == 0)	
		return 1		//end this helper background function
	endif
	
	//check if the count down is over
	variable cancelCountdown = str2num(getuserdata("pxpSavePanel","","cancelCountdown"))
	if (cancelCountdown > 0)
		Button cancelAutoSavePxp win=pxpSavePanel,title=("CANCEL pxp auto save\rstarting in ~"+num2str(cancelCountdown)+" secs")
		setwindow pxpSavePanel userdata(cancelCountdown)=num2str(cancelCountdown-1)		//iterate down the timer
		return 0		//continue count down
	endif
	
	//figure out if the experiment has been saved before
	String pxpName = igorinfo(1)
	int hasPxpName = cmpstr(pxpName,"Untitled",1) != 0		//Note: experiments actually saved as "Untitled.pxp" appear to be an issue
	if (hasPxpName)		//been saved before, so easy to just resave
		saveexperiment
	else			//name is "Untitled", indicating that pxp has not been saved (or at his been saved as "Untitled", which would be problematic at present!)
		int secs = datetime
		String timeStr = replacestring("-",secs2date(secs,-2),"_") +"_"+replacestring(":",secs2time(secs,3),"_")
		String savename = ks_autoSaveBaseName + timeStr + ".pxp"
		pathinfo IgorUserFiles
		print "experimentAutoSave() this pxp appears to be previously unsaved. Pxp will be saved with the automatically generated name:",savename,"in folder="+S_path
		saveexperiment/p=IgorUserFiles as savename
	endif
	
	killwindow pxpSavePanel		//kill the panel
	experimentmodified 0			//since we just killed the window, the experiment has been modified, but it's not a reason to save again next round, so mark experiment unmodified
	
	return 1		//end this helper background function
end

function cancelAutoSavePxpBtn(s) : ButtonControl
	STRUCT WMButtonAction &s
	
	if (s.eventcode != 2)		//only react to mouse up in button area
		return 0
	endif
	
	Ctrlnamedbackground pxpSaveHelperBgTask,kill=1
	killwindow pxpSavePanel
end

//end of functions for auto save
