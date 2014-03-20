############################################################################# 
## 
#W  ideals-acting.gi
#Y  Copyright (C) 2013-14                                 James D. Mitchell
## 
##  Licensing information can be found in the README file of this package. 
## 
############################################################################# 
##

# JDM: currently almost a straight copy from acting.gi

InstallMethod(SemigroupData, "for an acting semigroup ideal",
[IsActingSemigroup and IsSemigroupIdeal and HasGeneratorsOfSemigroupIdeal],
function(I)
  local gens, data, opts;
 
  gens:=GeneratorsOfSemigroup(Parent(I));

  data:=rec(gens:=gens, parent:=I,
     ht:=HTCreate(gens[1], rec(treehashsize:=I!.opts.hashlen.L)),
     pos:=0, graph:=[EmptyPlist(Length(gens))], init:=false,
     reps:=[], repslookup:=[], orblookup1:=[], orblookup2:=[], rholookup:=[fail],
     lenreps:=[0], orbit:=[fail,], dorbit:=[], repslens:=[],
     lambdarhoht:=[], schreierpos:=[fail], schreiergen:=[fail],
     schreiermult:=[fail], genstoapply:=[1..Length(gens)], stopper:=false);
  
  Objectify(NewType(FamilyObj(I), IsSemigroupIdealData), data);
  
  return data;
end);

#

InstallMethod(ViewObj, [IsSemigroupIdealData], 
function(data)
  Print("<");
  if IsClosedData(data) then 
    Print("closed ");
  else 
    Print("open ");
  fi;
  Print("semigroup ideal ");

  Print("data with ", Length(data!.orbit)-1, " reps, ",
   Length(LambdaOrb(data!.parent))-1, " lambda-values, ", 
   Length(RhoOrb(data!.parent))-1, " rho-values>"); 
  return;
end);

# We concentrate on the case when nothing is known about the parent of the
# ideal.

# we make the R-class centered data structure as in SemigroupData but at the
# same time have an additional "orbit" consisting of D-class reps. 

InstallMethod(Enumerate, 
"for semigroup ideal data, limit, and func",
[IsSemigroupIdealData, IsCyclotomic, IsFunction],
function(data, limit, lookfunc)
  local looking, ht, orb, nr_r, d, nr_d, graph, reps, repslens, lenreps, lambdarhoht, repslookup, orblookup1, orblookup2, rholookup, stopper, schreierpos, schreiergen, schreiermult, gens, nrgens, genstoapply, I, lambda, lambdao, lambdaoht, lambdalookup, lambdascc, lenscc, lambdaact, lambdaperm, rho, rhoo, rhooht, rhoolookup, rhoscc, act, htadd, htvalue, drel, dtype, UpdateSemigroupIdealData, idealgens, i, start, mults, scc, x, cosets, y, z, k, j;
 
  if lookfunc<>ReturnFalse then 
    looking:=true;
    data!.found:=false;
  else
    looking:=false;
  fi;
  
  if IsClosedData(data) then 
    if looking then 
      data!.found:=false;
    fi;
    return data;
  fi;
  
  data!.looking:=looking;

  ht:=data!.ht;       # so far found R-reps
  orb:=data!.orbit;   # the so far found R-reps data 
  nr_r:=Length(orb);
  d:=data!.dorbit;    # the so far found D-classes
  nr_d:=Length(d);
  graph:=data!.graph; # orbit graph of orbit of R-classes under left mult 
  reps:=data!.reps;   # reps grouped by equal lambda-scc-index and rho-value-index
 
  repslens:=data!.repslens;       # Length(reps[m][i])=repslens[m][i] 
  lenreps:=data!.lenreps;         # lenreps[m]=Length(reps[m])
  
  lambdarhoht:=data!.lambdarhoht; # HTValue(lambdarhoht, [m,l])=position in reps[m] 
                                  # of R-reps with lambda-scc-index=m and
                                  # rho-value-index=l
                      
  repslookup:=data!.repslookup; # Position(orb, reps[m][i][j])
                                # = repslookup[m][i][j]
                                # = HTValue(ht, reps[m][i][j])
  
  orblookup1:=data!.orblookup1; # orblookup1[i] position in reps[m] containing 
                                # orb[i][4] (the R-rep)

  orblookup2:=data!.orblookup2; # orblookup2[i] position in 
                                # reps[m][orblookup1[i]] 
                                # containing orb[i][4] (the R-rep)

  rholookup:=data!.rholookup;   #rholookup[i]=rho-value-index of orb[i][4]
  
  stopper:=data!.stopper;       # stop at this place in the orbit

  # schreier
  schreierpos:=data!.schreierpos;
  schreiergen:=data!.schreiergen;
  schreiermult:=data!.schreiermult;

  # generators
  gens:=data!.gens; # generators of the parent semigroup
  nrgens:=Length(gens); 
  genstoapply:=data!.genstoapply;
  
  I:=data!.parent;
  
  # lambda
  lambda:=LambdaFunc(I);
  lambdao:=LambdaOrb(I);
  lambdaoht:=lambdao!.ht;
  lambdalookup:=lambdao!.scc_lookup;
  lambdascc:=OrbSCC(lambdao); 
  lenscc:=Length(lambdascc);
  
  lambdaact:=LambdaAct(I);  
  lambdaperm:=LambdaPerm(I);
  
  # rho
  rho:=RhoFunc(I);
  rhoo:=RhoOrb(I); 
  rhooht:=rhoo!.ht;        
  rhoolookup:=rhoo!.scc_lookup;        
  rhoscc:=OrbSCC(rhoo); 

  act:=StabilizerAction(I);
 
  if IsBoundGlobal("ORBC") then 
    htadd:=HTAdd_TreeHash_C;
    htvalue:=HTValue_TreeHash_C;
  else
    htadd:=HTAdd;
    htvalue:=HTValue;
  fi;

  drel:=GreensDRelation(I);
  dtype:=DClassType(I);

  # the function which checks if x is already R/D-related to something in the
  # data and if not adds it in the appropriate place

  UpdateSemigroupIdealData:=function(x, pos, gen, idealpos)
    local new, xx, l, m, mm, schutz, mults, cosets, y, n, z, i, ind;
    
    new:=false;
   
    # check, update, rectify the lambda value
    xx:=lambda(x);
    l:=htvalue(lambdaoht, xx);
    if l=fail then 
      l:=UpdateIdealLambdaOrb(lambdao, xx, x, pos, gen, idealpos);
       
      # update the lists of reps
      for i in [lenscc+1..lenscc+Length(lambdascc)] do 
        reps[i]:=[];
        repslookup[i]:=[];
        repslens[i]:=[];
        lenreps[i]:=0;
        lenscc:=Length(lambdascc);
      od;
      new:=true; # x is a new R-rep
    fi;
    m:=lambdalookup[l];
    if l<>lambdascc[m][1] then 
      x:=x*LambdaOrbMult(lambdao, m, l)[2];
    fi;
    
    # check if x is identical to one of the known R-reps
    if not new then 
      if htvalue(ht, x)<>fail then 
        return; #x is one of the old R-reps
      fi;
    fi;
     
    # check, update, rectify the rho value
    xx:=rho(x);
    l:=htvalue(rhooht, xx);
    if l=fail then 
      l:=UpdateIdealRhoOrb(rhoo, xx, x, pos, gen, idealpos);
      new:=true; # x is a new R-rep
    fi;
    schutz:=LambdaOrbStabChain(lambdao, m);

    # check if x is R-related to one of the known R-reps
    if not new and schutz<>false and IsBound(lambdarhoht[l]) 
      and IsBound(lambdarhoht[l][m]) then 
       # if schutz=false or these are not bound, then x is a new R-rep
        
      if schutz=true then 
        return; 
      fi;
      
      ind:=lambdarhoht[l][m];
      for n in [1..repslens[m][ind]] do
        if SiftedPermutation(schutz, lambdaperm(reps[m][ind][n], x))=() then 
          return; # x is on of the old R-reps
        fi;
      od;
    fi;

    # if we reach here, then x is a new R-rep, and hence a new D-rep
    mm:=rhoolookup[l];
    if l<>rhoscc[mm][1] then 
      x:=RhoOrbMult(rhoo, mm, l)[2]*x;
    fi;
      
    nr_d:=nr_d+1;
    d[nr_d]:=rec();
    ObjectifyWithAttributes(d[nr_d], dtype, ParentAttr, I,
      EquivalenceClassRelation, drel, IsGreensClassNC, false, 
      Representative, x, LambdaOrb, lambdao, LambdaOrbSCCIndex, m,
      RhoOrb, rhoo, RhoOrbSCCIndex, mm, RhoOrbSCC, rhoscc[mm]);

    # install the R-class reps of the new D-rep
    mults:=RhoOrbMults(rhoo, mm);
    cosets:=RhoCosets(d[nr_d]);

    for l in rhoscc[mm] do #install the R-class reps
      if not IsBound(lambdarhoht[l]) then 
        lambdarhoht[l]:=[];
      fi;
      if not IsBound(lambdarhoht[l][m]) then 
        lenreps[m]:=lenreps[m]+1;
        ind:=lenreps[m];
        lambdarhoht[l][m]:=ind;
        repslens[m][ind]:=0;
        reps[m][ind]:=[];
        repslookup[m][ind]:=[];
      else
        ind:=lambdarhoht[l][m];
      fi;
      y:=mults[l][1]*x;

      for z in cosets do 
        nr_r:=nr_r+1;
        
        repslens[m][ind]:=repslens[m][ind]+1;
        reps[m][ind][repslens[m][ind]]:=act(y, z^-1);
        repslookup[m][ind][repslens[m][ind]]:=nr_r;
        orblookup1[nr_r]:=ind;
        orblookup2[nr_r]:=repslens[m][ind];
        rholookup[nr_r]:=l; 
        
        orb[nr_r]:=[I, m, lambdao, reps[m][ind][repslens[m][ind]], false, nr_r];
        htadd(ht, reps[m][ind][repslens[m][ind]], nr_r);
        
        if looking then 
          # did we find it?
          if lookfunc(data, orb[nr_r]) then 
            data!.found:=nr_r;
          fi;
        fi;

      od;
    od;
  end;
  
  # initialise the data if necessary
  if data!.init=false then 
    # add the generators of the ideal...
    idealgens:=GeneratorsOfSemigroupIdeal(I);
    for i in [1..Length(idealgens)] do
      UpdateSemigroupIdealData(idealgens[i], fail, fail, i);
    od;

    data!.init:=true;
  fi;
  i:=data!.pos;       # points in orb in position at most i have descendants

  while nr_d<=limit and i<nr_d and i<>stopper do 
    i:=i+1; # advance in the dorb
    
    # left multiply the R-class reps by the generators of the semigroup
    # JDM: this is repeated work...
    mults:=RhoOrbMults(rhoo, RhoOrbSCCIndex(d[i]));
    scc:=RhoOrbSCC(d[i]);
    x:=Representative(d[i]);
    cosets:=RhoCosets(d[i]);
    for y in cosets do 
      y:=act(x, y^-1);
      for j in scc do
        z:=mults[j][1]*y;
        for k in genstoapply do
          UpdateSemigroupIdealData(gens[k]*z, j, k, fail);
          if looking and data!.found<>false then 
            data!.pos:=i-1;
            return data;
          fi;
        od;
      od;
    od;
     
    # right multiply the L-class reps by the generators of the semigroup
    mults:=LambdaOrbMults(lambdao, LambdaOrbSCCIndex(d[i]));
    scc:=LambdaOrbSCC(d[i]);
    x:=Representative(d[i]);
    cosets:=LambdaCosets(d[i]);
    for y in cosets do 
      y:=act(x, y);
      for j in scc do
        z:=y*mults[j][1];
        for k in genstoapply do
          UpdateSemigroupIdealData(z*gens[k], j, k, fail);
          if looking and data!.found<>false then 
            data!.pos:=i-1;
            return data;
          fi;
        od;
      od;
    od;
    
  od;
  
  # for the data-orbit
  data!.pos:=i;
  
  if nr_d=i then 
    SetFilterObj(lambdao, IsClosed);
    SetFilterObj(rhoo, IsClosed);
    SetFilterObj(data, IsClosedData);
  fi;

  return data;
end);

#

InstallMethod(\in, 
"for an associative element and acting semigroup ideal",  
[IsAssociativeElement, IsActingSemigroup and IsSemigroupIdeal], 
function(x, I)
  local data, ht, xx, o, scc, scclookup, l, lookfunc, new, m, xxx, lambdarhoht, schutz, ind, reps, repslens, max, lambdaperm, oldrepslens, found, n, i;
  
  if ElementsFamily(FamilyObj(I))<>FamilyObj(x) 
    or (IsActingSemigroupWithFixedDegreeMultiplication(I) 
     and ActionDegree(x)<>ActionDegree(I)) 
    or (ActionDegree(x)>ActionDegree(I)) then 
    return false;
  fi;

  if ActionRank(I)(x)>MaximumList(List(Generators(I), f-> ActionRank(I)(x)))
   then
    Info(InfoSemigroups, 2, "element has larger rank than any element of ",
     "semigroup.");
    return false;
  fi;

  if HasMinimalIdeal(I) then 
    if ActionRank(I)(x)<ActionRank(I)(Representative(MinimalIdeal(I))) then
      Info(InfoSemigroups, 2, "element has smaller rank than any element of ",
       "semigroup.");
      return false;
    fi;
  fi;  

  data:=SemigroupData(I);
  ht:=data!.ht;

  # look for lambda!
  xx:=LambdaFunc(I)(x);   o:=LambdaOrb(I); 
  scc:=OrbSCC(o);         scclookup:=OrbSCCLookup(o);

  l:=Position(o, xx);

  if l=fail then 
    if IsClosed(o) then 
      return fail;
    fi;
     
    # this function checks if <pt> has the same lambda-value as x
    lookfunc:=function(data, pt) 
      return xx in o;
    end;
    Enumerate(data, infinity, lookfunc);
    l:=PositionOfFound(data);

    # rho is not found, so f not in s
    if l=false then 
      return false;
    fi;
    l:=Position(o, xx);
    new:=true;
  fi;
    
  # strongly connected component of lambda orb
  m:=OrbSCCLookup(o)[l];

  # make sure lambda of f is in the first place of its scc
  if l<>OrbSCC(o)[m][1] then 
    x:=x*LambdaOrbMult(o, m, l)[2];
  fi;
  
  # check if f is an existing R-rep
  if HTValue(ht, x)<>fail then 
    return true;
  fi;
  
  # look for rho!
  xxx:=RhoFunc(I)(x);   o:=RhoOrb(I); 
  scc:=OrbSCC(o);       scclookup:=OrbSCCLookup(o);

  l:=Position(o, xxx);

  if l=fail then 
    if IsClosed(o) then 
      return fail;
    fi;
     
    # this function checks if <pt> has the same lambda-value as x
    lookfunc:=function(data, pt) 
      return xxx in o;
    end;
    Enumerate(data, infinity, lookfunc);
    l:=PositionOfFound(data);

    # rho is not found, so f not in s
    if l=false then 
      return false;
    fi;
    l:=Position(o, xxx);
    new:=true;
  fi;
 
  lambdarhoht:=data!.lambdarhoht;

  # look for the R-class rep
  if not IsBound(lambdarhoht[l]) or not IsBound(lambdarhoht[l][m]) then 
    # lambda-rho-combination not yet seen
    if IsClosedData(data) then 
      return false;
    fi;
    
    lookfunc:=function(data, x)
      return IsBound(lambdarhoht[l]) and IsBound(lambdarhoht[l][m]);
    end;
    data:=Enumerate(data, infinity, lookfunc);
    if not IsBound(lambdarhoht[l]) or not IsBound(lambdarhoht[l][m]) then 
      return false;
    fi;
    new:=true;
  fi;

  o:=LambdaOrb(I); 
  schutz:=LambdaOrbStabChain(o, m);
  ind:=lambdarhoht[l][m];
  # the index of the list of reps with same lambda-rho value as f. 

  # if the Schutzenberger group is the symmetric group, then f in s!
  if schutz=true then 
    return true;
  fi;

  reps:=data!.reps;       repslens:=data!.repslens;
  max:=Factorial(LambdaRank(I)(xx))/Size(LambdaOrbSchutzGp(o, m));
  
  if repslens[m][ind]=max then 
    return true;
  fi;
  
  # if schutz is false, then f has to be an R-rep which it is not...
  if schutz<>false then 
    
    # check if f already corresponds to an element of reps[m][ind]
    lambdaperm:=LambdaPerm(I);
    for n in [1..repslens[m][ind]] do 
      if SiftedPermutation(schutz, lambdaperm(reps[m][ind][n], x))=() then
        return true;
      fi;
    od;
  elif new and HTValue(ht, x)<>fail then 
    return true; 
  fi; 

  if IsClosedData(data) then 
    return false;
  fi;

  # enumerate until we find x or finish 
  if repslens[m][ind]<max then 
    oldrepslens:=repslens[m][ind];
    lookfunc:=function(data, x)
      return repslens[m][ind]>oldrepslens;
    end; 
    if schutz=false then 
      repeat 
        # look for more R-reps with same lambda-rho value
        data:=Enumerate(data, infinity, lookfunc);
        oldrepslens:=repslens[m][ind];
        found:=data!.found;
        if found<>false then 
          if oldrepslens=max or x=data[found][4] then 
            return true;
          fi;
        fi;
      until found=false;
    else 
      repeat
        # look for more R-reps with same lambda-rho value
        data:=Enumerate(data, infinity, lookfunc);
        oldrepslens:=repslens[m][ind];
        found:=data!.found;
        if found<>false then
          if oldrepslens=max then 
            return true;
          fi;
          for i in [n+1..repslens[m][ind]] do 
            if SiftedPermutation(schutz, lambdaperm(reps[m][ind][i], x))=()
             then 
              return true;
            fi;
          od;
          n:=repslens[m][ind];
        fi;
      until found=false;
    fi;
  fi;
  return false;
end);

#EOF
