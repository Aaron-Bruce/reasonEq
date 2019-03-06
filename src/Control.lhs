\section{Control}
\begin{verbatim}
Copyright  Andrew Buttefield (c) 2019

LICENSE: BSD3, see file LICENSE at reasonEq root
\end{verbatim}
\begin{code}
module Control where

import Data.Map(Map)
import qualified Data.Map as M
import Control.Monad
\end{code}

We provide general flow-of-control constructs here,
often of a monadic flavour.

\subsection{Matching Controls}

\subsubsection{Matching types}
\begin{description}
  \item [\texttt{mp} :] instance of MonadPlus
  \item [\texttt{b} :]  binding type
  \item [\texttt{c} :] candidate type
  \item [\texttt{p} :] pattern type
\end{description}
We can then describe a standard (basic) match as:
\begin{code}
type BasicM mp b c p = c -> p -> b -> mp b
\end{code}

\subsubsection{Matching pairs}

\begin{code}
matchPair :: MonadPlus mp
          => BasicM mp b c1 p1 -> BasicM mp b c2 p2
          -> BasicM mp b (c1,c2) (p1,p2)

matchPair m1 m2 (c1,c2) (p1,p2) b  =   m1 c1 p1 b >>= m2 c2 p2
\end{code}

\subsubsection{Matching lists}

When we match lists sometimes we need to return
not just bindings,
but also something built from leftover list fragments
(usually before/after).
\begin{description}
  \item [\texttt{b'} :] binding plus extra stuff
\end{description}
\begin{code}
type Combine c b b' = [c] -> [c] -> b -> b'
\end{code}
In most cases we have the first list being those candidates before the match
(in reverse order, due to tail-recursion),
while the second is those after that match.
We typically want the binding with a single (ordered) list of the leftovers.
\begin{code}
defCombine :: Combine c b (b,[c])
defCombine sc cs b  = (b, reverse sc ++ cs)
\end{code}

\newpage
Matching many candidates against one pattern.
\begin{code}
manyToOne :: MonadPlus mp
          => BasicM mp b c p
          -> Combine c b b'
          -> [c] -> p -> b
          -> mp b'
manyToOne bf cf cs p b = manyToOne' bf cf [] p b cs

manyToOne' bf cf sc p b0 []      =  fail "no candidates"
manyToOne' bf cf sc p b0 (c:cs)  =  (do b <- bf c p b0 ; return $ cf sc cs b)
                                    `mplus`
                                    manyToOne' bf cf (c:sc) p b0 cs
\end{code}

Matching many candidates against many patterns.
\begin{code}
manyToMany :: MonadPlus mp
           => BasicM mp b c p
           -> Combine c b b'
           -> [c] -> [p] -> b
           -> mp b'
manyToMany bf cf cs ps b
 = foldr mplus (fail ".") $ map f ps
 where
   f p = manyToOne bf cf cs p b
\end{code}
