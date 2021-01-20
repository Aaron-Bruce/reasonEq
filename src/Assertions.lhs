\section{Assertions}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2021

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
{-# LANGUAGE PatternSynonyms #-}
module Assertions (
  Assertion, pattern Assertion, mkAsn, unwrapASN
, pattern AssnT, assnT, pattern AssnC, assnC
, normaliseQuantifiers
-- for testing onl
, normQTerm
) where
-- import Data.Char
-- import Data.List
import Data.Maybe
import Data.Set(Set)
import qualified Data.Set as S
import Data.Map(Map)
import qualified Data.Map as M

import Utilities (injMap, YesBut(..), unlines')
import Control (mapboth,mapaccum,mapsnd)
import LexBase
import Variables
import AST
import FreeVars
import SideCond

-- import Test.HUnit hiding (Assertion)
-- import Test.Framework as TF (defaultMain, testGroup, Test)
-- import Test.Framework.Providers.HUnit (testCase)
--import Test.Framework.Providers.QuickCheck2 (testProperty)

import Debug.Trace
dbg msg x = trace (msg++show x) x
pdbg nm x = dbg ('@':nm++":\n") x
\end{code}


\newpage
\subsection{Introduction}


An assertion is a predicate term coupled with side-conditions.
However,
we cannot simply pair a term and side-conditions in an arbitrary fashion.
There are conditions that have to be satisfied
in order for such a pairing to make sense.

An obvious one is that the general variables and variable-sets mentioned
in any assertion side-condition should appear somewhere in the assertion term.
Such a mismatch is inconvenient, or misleading, hence worth avoiding,
but it is not a show-stopper.


What is a show-stopper is when a side-condition refers to a variable by some
name, but the term contains multiple uses of that name,
that refer to \emph{different} variables.
This arises when a free variable's name is introduced in a binding sub-term.
Consider the following example:
\begin{equation}
   x = 3 \land P \land \exists x \bullet x < 10,  \quad x \notin P
   \label{eqn:assn:illformed}
\end{equation}
What does the $x$ in the side-condition refer to?
The first free $x$, or the second bound $x$, or both?

We consider such an assertion as being ill-formed.
It should be re-written, using $\alpha$-substitution,
so that it is clear which $x$ is meant in $x \notin P$.

The following three alternatives are fine:
\begin{eqnarray}
   x = 3 \land P \land \exists y \bullet y < 10, &&  x \notin P
   \label{eqn:assn:illfixx}
\\ x = 3 \land P \land \exists y \bullet y < 10, &&  y \notin P
   \label{eqn:assn:illfixy}
\\ x = 3 \land P \land \exists y \bullet y < 10, &&  x \notin P, y \notin P
   \label{eqn:assn:illfixxy}
\end{eqnarray}
What is clear,
is we cannot take
such a term as (\ref{eqn:assn:illformed}),
and transfrom it automatically into one of
(\ref{eqn:assn:illfixx})--(\ref{eqn:assn:illfixxy}).

Even without any side-condition being present,
it seems worth using $\alpha$-substitution
to ensure that all bound variables are distinct.
This means that we can use a single flat binding when matching terms.
However,
there are situations where we might want to
identify what in fact are distinct bound variables,
for pragmatic proof purposes.
Consider the following law:
$$
 (\forall x \bullet P(x) \land Q(x))
 \equiv
 (\forall x \bullet P(x)) \land (\forall x \bullet Q(x))
$$
This is logically equivalent,
provided $y$ and $z$ aren't already used inside $P$ or $Q$,
to
$$
 (\forall x \bullet P(x) \land Q(x))
 \equiv
 (\forall y \bullet P(y)) \land (\forall z \bullet Q(z))
$$
The question is, do we want the extra matches we might get
use the latter as a law?
Are there soundness issues if we use the former, with side-conditions on $x$?

A more concrete example is
the following one-point axiom for universal quantification:
$$
\AXAllOnePoint, \quad \AXAllOnePointS
$$
If we disambiguate bound variable $\lst y$ here,
we get the following, which is OK (provided $\lst z$ is fresh).
$$
   (\forall \lst x,\lst y
    \bullet \lst x = \lst e \implies P)
   \equiv
   (\forall \lst z \bullet p[\lst es/\lst xs][\lst z/\lst y]),
   \quad \lst x \notin \lst e
$$
Note that there is an implicit condition here that $\lst x$ and $\lst y$
denote distinct variable-sets.

The universal scope axiom is
$$
\AXorAllOScopeL \equiv \AXorAllOScopeR, \quad \AXorAllOScopeS
$$
Disambiguating bound variables leads to:
$$
\AXorAllOScopeL
\equiv
\forall \lst a \bullet
  P[\lst a/\lst x] \lor (\forall \lst b \bullet Q[\lst b/\lst y]),
  \quad \lst x \notin P, \lst a \notin P
$$
The side-condition $\lst x \notin P$ allows the following simplification:
$$
\AXorAllOScopeL
\equiv
\forall \lst a \bullet
  P \lor (\forall \lst b \bullet Q[\lst b/\lst y]),
  \quad \lst x \notin P, \lst a \notin P
$$
However, the original formulation of the axiom,
that re-uses bound $\lst x$ on both sides of the equivalence,
with (both) $\lst x$ not mentioned in $P$,
is precisely what we want.

The plan for now, is not to normalise anything,
but to check that any (observational)
variable mentioned in a side-condition
does have both free and bound occurrences.


\begin{code}
newtype Assertion = ASN (Term, SideCond) deriving (Eq,Ord,Show,Read)

pattern Assertion tm sc  <-  ASN (tm, sc)
pattern AssnT tm         <-  ASN (tm, _ )
pattern AssnC sc         <-  ASN (_,  sc)
\end{code}


We make an assertion by checking side-condition safety,
and then returning the assertion or signalling failure.
\begin{code}
mkAsn :: Monad m => Term -> SideCond -> m Assertion
mkAsn tm sc
  | safeSideCondition tm sc  = return ASN (tm, sc)
  | otherwise                = fail msg
  where
    msg = unlines' ["mkAsn: unsafe side-condition"
                   , "term = " ++ trTerm 0 tm
                   , "s.c. = " ++ trSideCond sc
                   ]
\end{code}

We can select assertion components by function,
and unwrap completely:
\begin{code}
assnT :: Assertion -> Term
assnT (ASN (tm, _))  =  tm

assnC :: Assertion -> SideCond
assnC (ASN (_, sc))  =  sc

unwrapASN :: Assertion -> (Term, SideCond)
unwrapASN (ASN tsc)  =  tsc
\end{code}


\subsection{Safe Side-Conditions}

A side-condition is safe w.r.t. a term if any observational variable
it mentions only occurs in the term as free, or bound, but not both.
This has to be true, not just at the top-level,
but at every level in the term syntax tree.
For example, $x$ would not be safe to use in a side-condition
in the following:
$$
  \forall x \bullet P(x) \lor \forall x \bullet Q(x)
$$
While it is not free at the top-level,
it is free within sub-term $P(x) \lor \forall x \bullet Q(x)$,
which is just as problematic.

We can define safety (for use in side-conditions)
of a given (observational) variable w.r.t. a given term.
Variable $x$ is safe w.r.t. $t$
if it is recursively safe in any sub-terms of $t$,
and its mode of use in those sub-terms, is then either all free or all bound.

We will look at the two universal quantification axioms that have
side-conditions with observational variables:
\begin{eqnarray}
   \AXorAllOScopeL \equiv \AXorAllOScopeR &,& \AXorAllOScopeS
   \label{eqn:ax:allscope}
\\ \AXAllOnePoint                         &,& \AXAllOnePointS
   \label{eqn:ax:all1pt}
\end{eqnarray}
The first (\ref{eqn:ax:allscope}) is straightforward,
as $\lst x$ only appears in binding occurrences.
The second (\ref{eqn:ax:all1pt}) seems problematic.
The LHS is ok, because $\lst x$ is only free in the quantifier body,
and is bound the the level of the LHS itself.
However, it seems to be free in the RHS,
as there is no (obvious) binding of $\lst x$ present.
However, the one use of it here is as the target variable of
a substitution, being replaced by $\lst e$.
In effect we treat the use of an observational variable as a substitution
target as being a binding occurrence,
as far as side-condition safety is concerned.
It is interesting to point out that the side condition itself is designed
to ensure that, indeed, $\lst x$ is not still free by virtue of mentioned
by $\lst e$.

We define usage of a variable as unused ($\bot$), free ($f$), or bound ($b$),
and a notion of ``lack of disagreement'' ($\simeq$),
and agreement ($\Join$):
\begin{eqnarray*}
   u \in U        &\defs& \setof{\bot,f,b}
\\ \_\simeq\_    &  :  & U \times U \fun \Bool
\\ f  \simeq b   &\defs& \false
\\ b  \simeq f   &\defs& \false
\\ \_ \simeq \_  &\defs& \true
\\ \_\Join\_       &  :  & U \times U \fun U
\\ \bot \Join u    &\defs& u
\\ u    \Join \bot &\defs& u
\\ u_1  \Join u_2  &\defs& u_1 \cond{u_1=u_2} \bot
\end{eqnarray*}
\def\scSafe{\textit{scSafe}}
\def\csafe{\textit{csafe}}
We can now define side-condition safety of $x$ w.r.t. $t$ as follows:
\begin{eqnarray*}
   \scSafe &:& V \fun T \fun \Bool
\\ \scSafe_x(t) &\defs& \pi_1(\csafe_x(t))
\\
\\ \csafe &:& V \fun T \fun \Bool \times U
\\ \csafe_x(v) &\defs& (\true,f) \cond{x=v} (\false,\bot)
\\ \csafe_x(p \land q)
   &\defs&   (ok_p \land ok_q \land u_p \simeq u_q, u_p \Join u_q)
\\ &\where& (ok_p,u_p) = \csafe_x(p)
\\ &      & (ok_q,u_q) = \csafe_x(q)
\\ \csafe_x(\forall v \bullet p)
   &\defs&   (ok_p,b) \cond{x = v}  (ok_p,u_p)
\\ &\where& (ok_p,u_p) = \csafe_x(p)
\\ \csafe_x(\_) &\defs& (\true,\bot)
\end{eqnarray*}

\subsection{Normalising Bound Variables}

\textbf{Note:}
\textsf{Currently buggy as free variables that occur syntactically later
than quantifier sub-terms will have none-zero numbering and so will
clash with bound variables}

We want all bound-variables to be unique in a term, so that, for example,
the term
$$
  \forall x \bullet x > y \land \exists x \bullet x = z + 42
  \qquad
  (\text{really:  }
   \forall x_0 \bullet x_0 > y_0 \land \exists x_0 \bullet x_0 = z_0 + 42)
$$
becomes:
$
  \forall x_i \bullet x_i > y_0 \land \exists x_j \bullet x_j = z_0 + 42
$
where $i > 0$, $j > 0$, and $i \neq j$.

Turns out there is a fairly simple algorithm, that doesn't require the
predicate to be zero'ed in advance!

\textbf{Note:}
\textit{
We need to be careful with non-substitutable terms!
}
\begin{eqnarray*}
   \theta,\mu : VV &\defs&  name \pfun \Nat
\\
\\ Norm &:& T \fun T
\\ Norm(p)                       &\defs& \pi_1(norm_\theta(p))
\\
\\ norm &:& VV \fun T \fun (T \times VV)
\\ norm_\mu(v)         &\defs & (v_{\mu(v)} \cond{v \in \mu} v_0,\mu)
\\ norm_\mu(e)         &\defs & (e,\mu)
\\ norm_\mu(P)         &\defs & (P,\mu)
\\ norm_\mu(p \land q) &\defs & (p' \land q',\mu'')
\\                     &\where& (p',\mu') = norm_\mu(p)
\\                     &      & (q',\mu'') = norm_{\mu'}(q)
\\ norm_\mu(p \seq q) &\defs & ((p;q)[mksub(\mu)],\mu)
\\ norm_\mu(\forall x \bullet p) &\defs& (\forall x_{\mu'(x)} \bullet p',\mu'')
\\                     &\where& \mu' = (\mu\override\maplet x 1)
                                       \cond{x \in \mu}
                                       (\mu\override\maplet x {\mu(x)+1})
\\                     &      & (p',\mu'') = norm_{\mu'}(p)
\end{eqnarray*}
\textbf{Note:}
\textsc{Bad idea!}
\textit{
``Note that we need to thread the  map parameter $\mu$ into and out of each call
to $norm$ to ensure that we get full uniqueness of bound variable numbers.''
}
\textbf{Correct approach:
  do not return VV map from each recursive call,
  so index = binding depth (``tree-local''),
  or keep as is, but note if inside a quantifier somehow (``total'').
}

\textbf{Note re Higher-Order predicates}
\textit{
If we go higher order, then \texttt{Cons} identifiers will have
to be normalised as well, as they might occur in quantifier lists.
Perhaps this is a better way to deal with generic truth functions,
such as $\odot$ from \cite[Ex. 2.1.2, p48]{UTP-book}.
}

We map bound variable names, and class and when attributes, to their unique numbers:
\begin{code}
type VarVersions = Map (String,VarClass,VarWhen) Int
\end{code}

We can also generate an explicit substitution from such a map:
\begin{code}
mkVVsubstn :: VarVersions -> Substn
mkVVsubstn vv
 = fromJust $ substn tsvv lvsvv
 where
   (tsvv,lvsvv) = unzip $ map mkvsubs $ M.assocs vv
   mkvsubs ((nm,cls,whn),u)
     = ((v0,tvu),(lv0,lvu))
     where
       v0 = Vbl (jId nm)    cls whn
       vu = Vbl (jIdU nm u) cls whn
       tvu = jVar (E ArbType) (Vbl (jIdU nm u) cls whn)
       lv0 = LVbl v0 [] []
       lvu = LVbl vu [] []
\end{code}

Quantifier normalisation:
\begin{code}
normaliseQuantifiers :: Term -> SideCond -> (Term, SideCond)
normaliseQuantifiers tm sc
  = let (tm', vv') = normQ M.empty tm
    in  (tm', normSC vv' sc)
\end{code}

\begin{code}
normQTerm :: Term -> Term
normQTerm tm = fst $ normaliseQuantifiers tm scTrue
\end{code}

\newpage

The real work is done here:
\begin{code}
normQ :: VarVersions -> Term -> (Term, VarVersions)
\end{code}

\begin{eqnarray*}
   norm_\mu(v)         &\defs & (v_{\mu(v)} \cond{v \in \mu} v_0,\mu)
\\ norm_\mu(e)         &\defs & (e,\mu)
\\ norm_\mu(P)         &\defs & (P,\mu)
\end{eqnarray*}
It is very important not to produce substitutions on term variables here.
\begin{code}
--normQ :: VarVersions -> Term -> (Term, VarVersions)
normQ vv (Var tk v@(Vbl (Identifier nm _) ObsV _))
                       =  ( fromJust $ var tk $ normQVar vv v, vv )
normQ vv v@(Var tk _)  =  ( v,                                 vv )
\end{code}

\begin{eqnarray*}
   norm_\mu(p \land q) &\defs & (p' \land q',\mu'')
\\                     &\where& (p',\mu') = norm_\mu(p)
\\                     &      & (q',\mu'') = norm_{\mu'}(q)
\\ norm_\mu(p \seq q) &\defs & ((p;q)[mksub(\mu)],\mu)
\end{eqnarray*}
\begin{code}
--normQ :: VarVersions -> Term -> (Term, VarVersions)
normQ vv t@(Cons tk sb n ts)
  | sb         =  (Cons tk sb n ts',vv')
  | otherwise  =  (Sub tk t s',vv)
  where
    (ts',vv') =  mapaccum normQ vv ts
    s' = mkVVsubstn vv
\end{code}

\begin{eqnarray*}
   norm_\mu(\forall x \bullet p) &\defs& (\forall x_{\mu'(x)} \bullet p',\mu'')
\\                     &\where& \mu' = (\mu\override\maplet x 1)
                                       \cond{x \in \mu}
                                       (\mu\override\maplet x {\mu(x)+1})
\\                     &      & (p',\mu'') = norm_{\mu'}(p)
\end{eqnarray*}
\begin{code}
--normQ :: VarVersions -> Term -> (Term, VarVersions)
normQ vv (Bnd tk n vs tm)
 = let (vl',vv') = normQBound vv $ S.toList vs
       (tm',vv'') =  normQ vv' tm
   in ( fromJust $ bnd tk n (S.fromList vl') tm', vv')
normQ vv (Lam tk n vl tm)
 = let (vl',vv') = normQBound vv vl
       (tm',vv'') =  normQ vv' tm
   in ( fromJust $ lam tk n vl' tm', vv')
normQ vv (Cls n tm)
 = let (_,vv') = normQBound vv $ filter isObsGVar $ S.toList $ freeVars tm
       (tm',vv'') = normQ vv' tm
   in ( Cls n tm',vv'')
\end{code}

\newpage
We don't have formal specs for these - straightforward?:
\begin{code}
--normQ :: VarVersions -> Term -> (Term, VarVersions)
normQ vv (Sub tk tm s)
  = let (tm',vv') = normQ vv tm
        (s',vv'') = normQSub vv' s
    in (Sub tk tm' s',vv'')

normQ vv (Iter tk sa na si ni lvs)
  =  (Iter tk sa na si ni $ map (normQLVar vv) lvs,vv)
\end{code}

Anything else is unchanged
\begin{code}
--normQ :: VarVersions -> Term -> (Term, VarVersions)
normQ vv trm = (trm, vv) -- Val, Typ
\end{code}


\subsection{Normalising Side-Conditions}

Working on side-conditions is tricky,
as they mention a variable that might have have been bound more than
once before normalisation.
The only safe thing to do here is duplicate the side-condition
for each version.
This means, for a side-condition variable $v$ mapped to $n$,
we need to produce $n+1$ side-conditions, for $v_0$ \dots $v_n$.
We call this process ``spanning''.
\begin{code}
normSC :: VarVersions -> SideCond -> SideCond
normSC vv (ascs,fvs)
  = case mkSideCond (map (normASC vv) ascs) (normFresh vv fvs) of
      Yes sc    ->  sc
      -- this should not fail, but just in case ...
      But msgs  ->  error ("normSC: "++unlines' msgs)

normASC vv (Disjoint gv vs)  =  Disjoint (normQGVar vv gv) (normQVSet vv vs)
normASC vv (Covers gv vs)    =  Covers   (normQGVar vv gv) (normQVSet vv vs)
normASC vv (IsPre gv)        =  IsPre    (normQGVar vv gv)

normFresh vv vs = normQVSet vv vs
\end{code}

\newpage

Functions that modify \texttt{VarVersions} \dots
\begin{code}
normQSub vv (Substn ts lvs)
  = let lvl' = mapboth (normQLVar vv) $ S.toList lvs
        (tl',vv') = normQTermSub vv $ S.toList ts
    in (fromJust $ substn tl' lvl', vv')

normQTermSub vv tl = mapaccum normQVarTerm vv tl

normQVarTerm vv (v,tm)
  = ((normQVar vv v, tm'), vv')
  where (tm',vv') = normQ vv tm

-- (vl',vv') = normQBound vv vl
normQBound vv [] = ([],vv)
normQBound vv (gv:gvs)
  = let (gv',vv') = normQBGVar vv gv
        (gvs',vv'') = normQBound vv' gvs
    in (gv':gvs', vv'')

normQBGVar vv (LstVar lv)
  =  let  (lv',vv') = normQBLVar vv lv  in  (LstVar lv', vv')
normQBGVar vv (StdVar v)
  =  let  (v', vv') = normQBVar  vv  v  in  (StdVar v',  vv')

normQBLVar vv (LVbl v is js)
  = let  (v',vv') = normQBVar vv v  in  (LVbl v' is js, vv')

normQBVar vv v@(Vbl (Identifier nm _) cls whn)
 = case M.lookup (nm,cls,whn) vv of
     Nothing  ->     ( setVarIdNumber 1 v,  M.insert (nm,cls,whn) 1  vv )
     Just u   ->  let u' = u+1
                  in ( setVarIdNumber u' v, M.insert (nm,cls,whn) u' vv )
\end{code}

Functions that lookup \texttt{VarVersions}\dots
\begin{code}
normQVSet :: VarVersions -> Set GenVar -> Set GenVar
normQVSet vv vs = S.fromList $ map (normQGVar vv) $ S.toList vs

normQVList vv vl = map (normQGVar vv) vl

normQGVar vv (StdVar v)   =  StdVar $ normQVar  vv v
normQGVar vv (LstVar lv)  =  LstVar $ normQLVar vv lv

normQLVar vv (LVbl v is js) = LVbl (normQVar vv v) is js

normQVar vv v@(Vbl (Identifier nm _) cls whn)
 = setVarIdNumber (M.findWithDefault 0 (nm,cls,whn) vv) v
\end{code}
