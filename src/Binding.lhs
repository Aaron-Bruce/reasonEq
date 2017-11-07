\section{Binding}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2017

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
{-# LANGUAGE PatternSynonyms #-}
module Binding
( VarBindRange
, pattern BindVar, pattern BindTerm
, LstVarBindRange
, pattern BindList, pattern BindSet
, Binding
, emptyBinding
, lookupBind
, lookupLstBind
, bindVarToVar
, bindVarToTerm
, bindLVarToVList
, bindLVarToVSet
, bindGVarToGVar
, bindGVarToVList
) where
--import Data.Maybe (fromJust)
import qualified Data.Map as M
import qualified Data.Set as S

--import Utilities
import LexBase
import AST
import VarData
\end{code}

\subsection{Binding Types}

We have two parts to a binding,
one for variables, the other for list-variables.
The first part maps a variable to either a variable or a term
of the appropriate form.
\begin{code}
data VarBindRange
  = BV Variable
  | BT Term
  deriving (Eq, Ord, Show, Read)

pattern BindVar  v = BV v
pattern BindTerm t = BT t

type VarBind = M.Map Variable VarBindRange
\end{code}

The other part maps a list variable to a list or set of variables.
\begin{code}
data LstVarBindRange
 = BL VarList
 | BS VarSet
 deriving (Eq, Ord, Show, Read)

pattern BindList vl = BL vl
pattern BindSet  vs = BS vs

type ListVarBind = M.Map ListVar LstVarBindRange
\end{code}

We put these together:
\begin{code}
newtype Binding = BD (VarBind, ListVarBind) deriving (Eq, Show, Read)

emptyBinding :: Binding
emptyBinding = BD (M.empty, M.empty)
\end{code}

\newpage
\subsection{Binding Lookup}

Binding lookup is very straightforward,
with the minor wrinkle that we want to do it
in a general monadic setting.
\begin{code}
lookupBind :: Monad m => Binding -> Variable -> m VarBindRange
lookupBind (BD (vbinds,_)) v
  = case M.lookup v vbinds of
      Nothing   ->  fail ("lookupBind: Variable "++show v++" not found.")
      Just vbr  ->  return vbr

lookupLstBind :: Monad m => Binding -> ListVar -> m LstVarBindRange
lookupLstBind (BD (_,lbinds)) lv
  = case M.lookup lv lbinds of
      Nothing    ->  fail ("lookupLstBind: ListVar "++show lv++"not found.")
      Just lvbr  ->  return lvbr
\end{code}

\subsection{Binding Insertion}

Insertion is more complicated,
as we have to ensure that the variable classification
matches the kind of thing to which it is being bound.
Observation pattern variables can match variables and expressions,
while expression and predicate pattern variables can only
match expressions and predicates respectively.

We have a design choice here: if we call the insertion function with
an innappropriate variable/thing mix, do we simply return the binding
unaltered, or do we fail?
We shall adopt the principle of failing in a general monadic setting,
noting however that the matching code we develop
should never fail in this way.

\subsubsection{Binding Variable to Variable}

Variables can only bind to variables with the same

\begin{code}
bindVarToVar :: Monad m => Variable -> Variable -> Binding -> m Binding
bindVarToVar pv cv (BD (vbinds,lbinds))
 | compatibleVV pv cv
    = return $ BD (M.insert pv (BV cv) vbinds,lbinds)
 | otherwise
    = fail $ unlines
        [ "bindVarToVar: incompatible variables"
        , "pv = " ++ show pv
        , "cv = " ++ show cv
        ]
\end{code}

Compatible var.-var. bindings:
\begin{code}
compatibleVV (ObsVar _ _) (ObsVar _ _) = True
compatibleVV (ObsVar _ _) (ExprVar _ _) = True
compatibleVV (VarVar _ _) (VarVar _ _) = True
compatibleVV (ExprVar _ _) (ExprVar _ _) = True
compatibleVV (PredVar _ _) (PredVar _ _) = True
compatibleVV _ _  = False
\end{code}

\newpage
\subsubsection{Binding Variable to Term}

An observation or expression variable can bind to an expression
while a predicate variable can only bind to a predicate.
If we are binding an observation to a term with variant \texttt{Var},
we bind to the underlying variable.
\begin{code}
bindVarToTerm :: Monad m => Variable -> Term -> Binding -> m Binding
bindVarToTerm pv@(ObsVar _ _) ct@(Var _ cv) (BD (vbinds,lbinds))
  | isExpr ct  = return $ BD (M.insert pv (BV cv) vbinds,lbinds)
bindVarToTerm pv@(ObsVar _ _) ct (BD (vbinds,lbinds))
  | isExpr ct  = return $ BD (M.insert pv (BT ct) vbinds,lbinds)
bindVarToTerm pv@(ExprVar _ _) ct (BD (vbinds,lbinds))
  | isExpr ct  = return $ BD (M.insert pv (BT ct) vbinds,lbinds)
bindVarToTerm pv@(PredVar _ _) ct (BD (vbinds,lbinds))
  | isPred ct  = return $ BD (M.insert pv (BT ct) vbinds,lbinds)
bindVarToTerm _ _ _ = fail "bindVarToTerm: invalid var. -> term binding."
\end{code}

\subsubsection{Binding List-Variables to Variable-Lists}

An observation list-variable can bind to a list that is
a mix of observation and expression general variables.
\begin{code}
isObsOrExpr gv = isObsGVar gv || isExprGVar gv
\end{code}
Expression/Predicate list-variables can only bind to lists
of the same class of general variable.
\begin{code}
bindLVarToVList :: Monad m => ListVar -> VarList -> Binding -> m Binding
bindLVarToVList lv vl (BD (vbinds,lbinds))
 | isObsLVar lv && all isObsOrExpr vl
                               = return $ BD (vbinds,M.insert lv (BL vl) lbinds)
 | isExprLVar lv && all isExprGVar vl
                               = return $ BD (vbinds,M.insert lv (BL vl) lbinds)
 | isPredLVar lv && all isPredGVar vl
                               = return $ BD (vbinds,M.insert lv (BL vl) lbinds)
bindLVarToVList _ _ _ = fail "bindLVarToVList: invalid lvar. -> vlist binding."
\end{code}

\subsubsection{Binding List-Variables to Variable-Sets}

An observation list-variable can bind to a set that is
a mix of observation and expression general variables.
Expression/Predicate list-variables can only bind to sets
of the same class of general variable.
\begin{code}
bindLVarToVSet :: Monad m => ListVar -> VarSet -> Binding -> m Binding
bindLVarToVSet lv vs (BD (vbinds,lbinds))
 | isObsLVar lv && all isObsOrExpr vl
                               = return $ BD (vbinds,M.insert lv (BS vs) lbinds)
 | isExprLVar lv && all isExprGVar vl
                               = return $ BD (vbinds,M.insert lv (BS vs) lbinds)
 | isPredLVar lv && all isPredGVar vl
                               = return $ BD (vbinds,M.insert lv (BS vs) lbinds)
 where vl = S.toList vs
bindLVarToVSet _ _ _ = fail "bindLVarToVSet: invalid lvar. -> vset binding."
\end{code}

\subsubsection{Binding General-Variables to General-Variables}

An list-variable can bind to a singleton list of any general variable,
while a standard-variable can only bind to a standard variable.
\begin{code}
bindGVarToGVar :: Monad m => GenVar -> GenVar -> Binding -> m Binding
bindGVarToGVar (LstVar lv) gv binds = bindLVarToVList lv [gv] binds
bindGVarToGVar (StdVar pv) (StdVar cv) binds = bindVarToVar pv cv binds
bindGVarToGVar _ _ _ = fail "bindGVarToGVar: invalid stdvar. -> lstvar. binding."
\end{code}

\subsubsection{Binding General-Variables to Variable-Lists}

An list-variable can bind to a list of any length,
while a standard-variable can only bind to the standard variable inside
a singleton list.
\begin{code}
bindGVarToVList :: Monad m => GenVar -> VarList -> Binding -> m Binding
bindGVarToVList (LstVar lv) vl binds = bindLVarToVList lv vl binds
bindGVarToVList (StdVar pv) [StdVar cv] binds = bindVarToVar pv cv binds
bindGVarToVList _ _ _ = fail "bindGVarToVList: invalid gvar. -> vlist binding."
\end{code}
