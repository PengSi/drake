function tree=testGui

% Opens a gui for running unit tests
%

% todo: add buttons on the top for (a) reloading unit tests, (b) megaclear

h=figure(1302); clf
clear global runNode_mutex;

data=struct('pass',0,'fail',0,'wait',0);
root = uitreenode('v0','All Tests',sprintf('<html>All Tests &nbsp;&nbsp;<i>(passed:%d, failed:%d, not yet run:%d)</i></html>',data.pass,data.fail,data.wait),[matlabroot, '/toolbox/matlab/icons/greenarrowicon.gif'],false);
set(root,'UserData',data);
crawlDir('examples',root,false);

[tree,treecont] = uitree('v0','Root',root);
expandAll(tree,root);
%crawlDir('.',root,true);

hbutton1 = uicontrol('String','Halt Tests','callback',@(h,env) cleanup(h,env,tree),'BusyAction','cancel');
hbutton2 = uicontrol('String','Reset Unit Tests','callback',@(h,env) reloadGui(h,env,tree),'BusyAction','cancel');

set(tree,'NodeSelectedCallback', @runSelectedNode);
set(treecont,'BusyAction','queue');
resizeFcn([],[],treecont,hbutton1,hbutton2);
set(h,'MenuBar','none','ToolBar','none','Name','Drake Unit Tests','NumberTitle','off','ResizeFcn',@(src,ev)resizeFcn(src,ev,treecont,hbutton1,hbutton2),'WindowStyle','docked');

end

function tree=reloadGui(h,env,tree)
  megaclear;
  load drake_config;
  cd(conf.root);
  tree=testGui;
end

function cleanup(h,env,tree)
  userdata={};
  iter = tree.getRoot.breadthFirstEnumeration;
  while iter.hasMoreElements;
    node = iter.nextElement;
    if (node.isLeaf)
      d = get(node,'UserData');
      if ~isfield(d,'test'), continue; end  % false leaf
      userdata{end+1} = get(node,'UserData');
    end
  end
  backupname = '.testGuiData.mat';
  save(backupname,'userdata');
  tree=reloadGui(h,env,tree);
  load(backupname);
  delete(backupname);
  
  iter = tree.getRoot.breadthFirstEnumeration;
  while iter.hasMoreElements;
    node = iter.nextElement;
    if (node.isLeaf)
      d = get(node,'UserData');
      if ~isfield(d,'test'), continue; end % false leaf
      pathmatches = userdata(strcmp(d.path,cellfun(@(a) getfield(a,'path'),userdata,'UniformOutput',false)));
      if (~isempty(pathmatches))
        testmatch = pathmatches(strcmp(d.test,cellfun(@(a) getfield(a,'test'),pathmatches,'UniformOutput',false)));
        if (~isempty(testmatch))
          set(node,'UserData',testmatch{1});
          switch (testmatch{1}.status)
            case 0
              % do nothing, already set to wait
            case 1
              updateParentNodes(node.getParent,'wait',-1);
              updateParentNodes(node.getParent,'pass',1);
              node.setName(['<html><font color="green">[PASSED]</font> ',d.test,'</html>']);
            case 2
              updateParentNodes(node.getParent,'wait',-1);
              updateParentNodes(node.getParent,'fail',1);
              node.setName(['<html><font color="red"><b>[FAILED]</b></font> ',d.test,'</html>']);
          end
          tree.reloadNode(node);
        end
      end
    end
  end
end

function resizeFcn(src,ev,treecont,hbutton1,hbutton2)
  pos = get(gcf,'Position');
  set(hbutton1,'Position',[0,pos(4)-20,pos(3)/2,20]);
  set(hbutton2,'Position',[pos(3)/2,pos(4)-20,pos(3)/2,20]);
  set(treecont,'Position',[0,0,pos(3),pos(4)-20]);
end

function expandAll(tree,node)
  tree.expand(node);
  iter = node.breadthFirstEnumeration;
  while iter.hasMoreElements
    tree.expand(iter.nextElement);
  end
end

function pnode = crawlDir(pdir,pnode,only_test_dirs)

  p = pwd;
  cd(pdir);
  
  data=struct('pass',0,'fail',0,'wait',0);
  node = uitreenode('v0',pdir,['<html>',pdir,sprintf(' &nbsp;&nbsp;<i>(passed:%d, failed:%d, not yet run:%d)</i></html>',data.pass,data.fail,data.wait)],[matlabroot, '/toolbox/matlab/icons/greenarrowicon.gif'],false);
  set(node,'UserData',data);
  pnode.add(node);
  files=dir('.');
  
  for i=1:length(files)
    if (files(i).isdir)
      % then recurse into the directory
      if (files(i).name(1)~='.' && ~any(strcmpi(files(i).name,{'dev','slprj','autogen-matlab','autogen-posters'})))  % skip . and dev directories
        crawlDir(files(i).name,node,only_test_dirs && ~strcmpi(files(i).name,'test'));
      end
      continue;
    end
    if (only_test_dirs) continue; end

    if (~strcmpi(files(i).name(end-1:end),'.m')) continue; end
    if (strcmpi(files(i).name,'Contents.m')) continue; end
    
    testname = files(i).name;
    ind=find(testname=='.',1);
    testname=testname(1:(ind-1));
    
    isClass = checkFile(files(i).name,'classdef');
    if (isClass)
      if (checkClass(files(i).name,'NOTEST'))
        continue; 
      end
      m = staticMethods(testname);
      for j=1:length(m)
        if (checkMethod(files(i).name,m{j},'NOTEST'))
          disp(['skipping ',testname,'.',m{j}]);
          continue;
        end
        
        node = addTest(node,[testname,'.',m{j}]);
      end
      
    else
      % reject if there is a notest
      if (checkFile(files(i).name,'NOTEST'))
        continue;
      end
      node = addTest(node,testname);
    end
    
  end
  cd(p);
end

function node = addTest(node,testname)
  data=struct('path',pwd,'test',testname,'status',0);
  n = uitreenode('v0',testname,['<html>',testname,'</html>'],[matlabroot, '/toolbox/matlab/icons/greenarrowicon.gif'],true);
  set(n,'UserData',data);
  node.add(n);
  
  updateParentNodes(node,'wait',1);
end

function updateParentNodes(node,field,delta)
  data = get(node,'UserData');
  data = setfield(data,field,getfield(data,field)+delta);
  set(node,'UserData',data);
  v = get(node,'Value');
  if (data.fail>0)
    node.setName(['<html>',v,sprintf(' &nbsp;&nbsp;<i>(passed:%d, <font color="red"><b>failed:%d</b></font>, not yet run:%d)</i></html>',data.pass,data.fail,data.wait)]);
  else
    node.setName(['<html>',v,sprintf(' &nbsp;&nbsp;<i>(passed:%d, failed:%d, not yet run:%d)</i></html>',data.pass,data.fail,data.wait)]);
  end
  
  if ~isempty(node.getParent)
    updateParentNodes(node.getParent,field,delta);
  end
end

function runSelectedNode(tree,ev)
  nodes = tree.getSelectedNodes;
  if (~isempty(nodes))
    node=nodes(1);
    runNode(tree,node);
    tree.setSelectedNode([]);
  end
end

function runNode(tree,node)
  data = get(node,'UserData');
  if (isfield(data,'test'))
    global runNode_mutex;
    if ~isempty(runNode_mutex)
      node.setName(['<html><font color="gray">[WAITING]</font> ',data.test,'</html>']);
      tree.reloadNode(node);
      runNode_mutex{end+1}=node;
      return;
    end
    runNode_mutex{1}=node;
    
    node.setName(['<html><font color="blue">[RUNNING]</font> ',data.test,'</html>']);
    tree.reloadNode(node);
    
    pass = runTest(data.path,data.test);
    
    switch(data.status)
      case 0
        updateParentNodes(node.getParent,'wait',-1);
      case 1
        updateParentNodes(node.getParent,'pass',-1);
      case 2
        updateParentNodes(node.getParent,'fail',-1);
    end
      
    if (pass)
      node.setName(['<html><font color="green">[PASSED]</font> ',data.test,'</html>']);
      data.status = 1;
      updateParentNodes(node.getParent,'pass',1);
      set(node,'UserData',data);
    else
      node.setName(['<html><font color="red"><b>[FAILED]</b></font> ',data.test,'</html>']);
      data.status = 2;
      updateParentNodes(node.getParent,'fail',1);
      set(node,'UserData',data);
    end
    tree.reloadNode(node);
    if (exist('runNode_mutex'))
      torun = runNode_mutex(2:end);
      runNode_mutex = [];
    
      for i=1:length(torun)
        runNode(tree,torun{i});
      end
    else
      warning(['test:', data.test,' cleared the global variables. bad form. the queue of waiting tests has been lost']); 
    end
  else
    iter = node.depthFirstEnumeration;
    while iter.hasMoreElements
      n=iter.nextElement;
      d=get(n,'UserData');
      if isfield(d,'test')
        runNode(tree,n);
      end
    end
  end
end

function pass = runTest(path,test)
  p=pwd;
  cd(path);
%  disp(['running ',path,'/',test,'...']);

  s=dbstatus;
  % useful for debugging: if 'dbstop if error' is on, then don't use try catch. 
  if any(strcmp('error',{s.cond})) ||any(strcmp('warning',{s.cond}))
    feval(test);
  else
    try
      feval(test);
    catch ex
      pass = false;
      cd(p);
      disp(getReport(ex,'extended'));
      %    rethrow(ex);
      return;
    end
  end
  
  a=warning;
  if (~strcmp(a(1).state,'on'))
    error('somebody turned off warnings on me!');  % see bug
  end
  
  pass = true;
  cd(p);
end

function bfound = checkFile(filename,strings)
% opens the file and checks for the existence of the string (or strings)

if ~iscell(strings), strings = {strings}; end

bfound = false;
fid=fopen(filename);
if (fid<0) return; end  % couldn't open the file.  skip it.
while true  % check the file for the strings
  tline = fgetl(fid);
  if (~ischar(tline))
    break;
  end
  for i=1:length(strings)
    if (~isempty(strfind(tline,strings{i})))
      fclose(fid);
      bfound = true;
      return;
    end
  end
end
fclose(fid);

end

function bfound = checkClass(filename,strings)

if ~iscell(strings), strings = {strings}; end
strings = lower(strings);

bfound = false;
bInMethod = false;
endcount = 0;
fid=fopen(filename);
if (fid<0) return; end  % couldn't open the file.  skip it.
while true  % check the file for the strings
  tline = fgetl(fid);
  if (~ischar(tline))
    break;
  end
  tline = lower(tline);
  commentind = strfind(tline,'%');
  if (~isempty(commentind)) tline = tline(1:commentind(1)-1); end
  if (~bInMethod && ~isempty(strfind(tline,'function')))
    bInMethod = true;
    endcount=0;
  end
  if (bInMethod)
    strings={'for','while','switch','try','if'};
    endcount = endcount + length(keywordfind(tline,strings));
    endcount = endcount - length(keywordfind(tline,'end'));
%    disp([num2str(endcount,'%2d'),': ',tline]);
    if endcount<0
      bInMethod=false;
    end
  end
end
fclose(fid);

end

function bfound = checkMethod(filename,methodname,strings)

if ~iscell(strings), strings = {strings}; end
strings = lower(strings);

bfound = false;
bInMethod = false;
endcount = 0;
fid=fopen(filename);
if (fid<0) return; end  % couldn't open the file.  skip it.
while true  % check the file for the strings
  tline = fgetl(fid);
  if (~ischar(tline))
    break;
  end
  tline = lower(tline);
  commentind = strfind(tline,'%');
  if (~isempty(commentind)) tline = tline(1:commentind(1)-1); end
  if (~bInMethod && ~isempty(strfind(tline,'function')))
    if (~isempty(strfind(tline,lower(methodname))))
      bInMethod = true;
      endcount=0;
    end
  end
  if (bInMethod)
    endcount = endcount + length(keywordfind(tline,{'for','while','switch','try','if'}));
    endcount = endcount - length(keywordfind(tline,'end'));
    
    for i=1:length(strings)
      if (~isempty(strfind(tline,strings{i})))
        fclose(fid);
        bfound = true;
        return;
      end
    end
%    disp([num2str(endcount,'%2d'),': ',tline]);
    if endcount<0
      fclose(fid);
      return;
    end
  end
end
fclose(fid);

end


function inds = keywordfind(line,strs)

if (~iscell(strs)) strs={strs}; end

inds=[];
for i=1:length(strs)
  s = strs{i};
  a = strfind(line,s);
  % check that it is bracketed by a non-letter
  j=1;
  while j<=length(a)
    if (a(j)~=1 && isletter(line(a(j)-1)))
      a(j)=[];
      continue;
    end
    if (a(j)+length(s)<=length(line) && isletter(line(a(j)+length(s))))
      a(j)=[];
      continue;
    end
    inds=[inds,a(j)];
    j=j+1;
  end
end  

end
