\section{Term and Match Ranking}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2017--18

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
module Ranking
  ( FilterFunction, OrderFunction, Ranking
  , filterAndSort -- used in Main
  -- exported Filters
  , acceptAll -- not used
  , isNonTrivial-- used in REqState
  , nonTrivialQuantifiers -- used in REqState
  , noFloatingVariables -- used in REqState
  -- exported Orderings
  , sizeOrd -- not used
  , favourDefLHSOrd -- used in Main
  -- exported rankings
  , sizeRanking -- not used
  , favouriteRanking -- not used
  )
where

import Data.List (sortOn)
import qualified Data.Set as S

import Utilities
import Variables
import AST
import Binding
import Laws
import Proofs
import Instantiate
import LiveProofs
import TestRendering

import Debug.Trace
dbg msg x = trace (msg++show x) x
pdbg nm x = dbg ('@':nm++":\n") x
mdbg msg mtchs = trace (msg++":\n"++unlines (map mdetails mtchs)) mtchs
mdebug mtch = trTerm 0 $ mRepl mtch
mdetails mtch
   = mName mtch
     ++ " @ " ++ showMatchClass (mClass mtch)
     ++ " -->  " ++ trTerm 0 (mRepl mtch)
\end{code}

\subsection{Ranking Types}

Ranking involves two phases: filtering, and ordering.
Filtering is using a predicate to decide what matches to consider
for ranking.
Ordering is done by computing a $n$-tuple of values ($n \geq 1$),
to be used in sorting comparisons.
The values should belong to a type that has an instance of \texttt{Ord},
so that the tuple itself is also an instance of \texttt{Ord}.
\begin{code}
type FilterFunction = [MatchContext] -> Match -> Bool
type OrderFunction ord = [MatchContext] -> Match -> ord
type Ranking = [MatchContext] -> Matches -> Matches
\end{code}

\newpage
\subsection{Ranking Match Lists}

Simple sorting according to rank,
with duplicate replacements removed
(this requires us to instantiate the replacements).
\begin{code}
filterAndSort :: Ord ord
              => (FilterFunction, OrderFunction ord) -> [MatchContext]
              -> Matches -> Matches
filterAndSort (ff,rf) ctxts ms
  =  reverse $ remDupRepl $ reverse sms
  -- we double reverse to ensure duplicates favour "earlier" theories
  -- such as `Equiv`.
  where
    fms = filter (ff ctxts) ms
    sms = map snd $ sortOn fst $ zip (map (rf ctxts) fms) fms

remDupRepl :: [ Match  ] -> [ Match ]
--  original mRepl matches with unique instantiations.
remDupRepl []       =  []
remDupRepl [m]  =  [m]
remDupRepl (m1:rest@(m2:ms))
  | sameRepl m1 m2  =       remDupRepl (m1:ms)
  | otherwise       =  m1 : remDupRepl rest

sameRepl :: Match -> Match -> Bool
sameRepl m1 m2 = mRepl m1 == mRepl m2
\end{code}

\subsection{Rankings}


\subsubsection{Size Matters}

\begin{code}
sizeRanking :: Ranking
sizeRanking = filterAndSort ( acceptAll, sizeOrd )
\end{code}

\subsubsection{No Vanishing Q, favour LHS}

\begin{code}
favouriteRanking  :: Ranking
favouriteRanking = filterAndSort ( nonTrivialQuantifiers, favourDefLHSOrd )
\end{code}


\newpage
\subsection{Filters}

\subsubsection{Accept All}

\begin{code}
acceptAll :: FilterFunction
acceptAll _ _ = True
\end{code}

\subsubsection{Drop Trivial Matches}

Reject matches against a single predicate variable
\begin{code}
isNonTrivial :: FilterFunction
isNonTrivial _ m
  =  nontrivial $ mClass m
  where
     nontrivial (MatchEqvVar _)  =  False
     nontrivial _                =  True
\end{code}

\subsubsection{Drop Vanishing Quantifiers}

Often we do not want matches in which all pattern list-variables
are mapped to empty sets and lists.
\begin{code}
nonTrivialQuantifiers :: FilterFunction
nonTrivialQuantifiers _  =  not . onlyTrivialQuantifiers . mBind
\end{code}

\subsubsection{Drop Floating Matches}

\begin{code}
noFloatingVariables :: FilterFunction
noFloatingVariables _ =   not . any isFloatingGVar . mentionedVars . mRepl
\end{code}

\newpage
\subsection{Orderings}

In orderings, smaller is better.

\subsubsection{Term Size}

Simple ranking by replacement term size,
after the binding is applied:
\begin{code}
sizeOrd :: OrderFunction Int
sizeOrd _ m  =  termSize $ mRepl m

termSize :: Term -> Int
termSize (Val _ _)            =  1
termSize (Var _ _)            =  1
termSize (Cons _ _ _ ts)      =  1 + sum (map termSize ts)
termSize (Bnd _ _ vs t)       =  1 + S.size vs + termSize t
termSize (Lam _ _ vl t)       =  1 + length vl + termSize t
termSize (Cls _ t)            =  1 + termSize t
termSize (Sub _ t subs)       =  1 + termSize t + subsSize subs
termSize (Iter _ _ _ _ _ vl)  =  3 + length vl
termSize (Typ _)              =  2

subsSize (Substn ts lvs)      =  3 * S.size ts + 2 * S.size lvs
\end{code}


\subsubsection{Favour LHS and Definitions}

Show matches to laws named as definitions first,
then those matching LHS of equivalence laws,
and then the rest.
\begin{code}
favourDefLHSOrd :: OrderFunction (Int,Int,Int)
favourDefLHSOrd ctxt m
  = ( subMatchDef $ mName m
    , subMatchOrd $ mClass m
    , sizeOrd ctxt m
    )

subMatchDef :: String -> Int
subMatchDef lawname
 | take 4 (reverse lawname) == "fed_"  =  0
 | otherwise                           =  1

subMatchOrd :: MatchClass -> Int
subMatchOrd MatchAll         =  0
subMatchOrd MatchEqvLHS      =  1
subMatchOrd MatchEqvRHS      =  2
subMatchOrd (MatchEqv _)     =  2
subMatchOrd MatchAnte        =  3
subMatchOrd MatchCnsq        =  3
subMatchOrd (MatchEqvVar _)  =  3
\end{code}
