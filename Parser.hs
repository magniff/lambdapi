module Parser where

import Prelude hiding (print)
import Control.Monad.Error
import Data.List
import Data.Char
import Text.PrettyPrint.HughesPJ hiding (parens)
import qualified Text.PrettyPrint.HughesPJ as PP
import Text.ParserCombinators.Parsec hiding (parse, State)
import qualified Text.ParserCombinators.Parsec as P
import Text.ParserCombinators.Parsec.Token
import Text.ParserCombinators.Parsec.Language
import System.Console.Readline
import System.IO hiding (print)
import System.IO.Error hiding (try)

import LPH

putstrln x = putStrLn x
simplyTyped = makeTokenParser (haskellStyle { identStart = letter <|> P.char '_',
                                              reservedNames = ["let", "assume", "putStrLn"] })
lambdaPi = makeTokenParser (haskellStyle { identStart = letter <|> P.char '_',
                                           reservedNames = ["forall", "let", "assume", "putStrLn", "out"] })

parseBindings :: CharParser () ([String], [Info])
parseBindings = 
                   (let rec :: [String] -> [Info] -> CharParser () ([String], [Info])
                        rec e ts =
                          do
                           (x,t) <- parens lambdaPi
                                      (do
                                         x <- identifier simplyTyped 
                                         reserved simplyTyped "::"
                                         t <- pInfo
                                         return (x,t))
                           (rec (x : e) (t : ts) <|> return (x : e, t : ts))
                    in rec [] [])
                   <|>
                   do  x <- identifier simplyTyped 
                       reserved simplyTyped "::"
                       t <- pInfo
                       return ([x], [t])
  where
    pInfo = fmap HasType (parseType 0 []) <|> fmap (const (HasKind Star)) (reserved simplyTyped "*")
parseStmt :: [String] -> CharParser () (Stmt ITerm Info)
parseStmt e =
      do
        reserved simplyTyped "let"
        x <- identifier simplyTyped
        reserved simplyTyped "="
        t <- parseITerm 0 e
        return (Let x t)
  <|> do
        reserved simplyTyped "assume"
        (xs, ts) <- parseBindings
        return (Assume (reverse (zip xs ts)))
  <|> do
        reserved simplyTyped "putStrLn"
        x <- stringLiteral simplyTyped
        return (PutStrLn x)
  <|> do
        reserved lambdaPi "out"
        x <- option "" (stringLiteral simplyTyped)
        return (Out x)
  <|> fmap Eval (parseITerm 0 e)
parseType :: Int -> [String] -> CharParser () Type
parseType 0 e =
  try
     (do
        t <- parseType 1 e
        rest t <|> return t)
  where
    rest t =
      do
        reserved simplyTyped "->"
        t' <- parseType 0 e
        return (Fun t t')
parseType 1 e =
      do
        x <- identifier simplyTyped
        return (TFree (Global x))
  <|> parens simplyTyped (parseType 0 e)
parseITerm :: Int -> [String] -> CharParser () ITerm
parseITerm 0 e =
  try
     (do
        t <- parseITerm 1 e
        return t)
parseITerm 1 e =
  try
     (do
        t <- parseITerm 2 e
        rest (Inf t) <|> return t)
  <|> do
        t <- parens simplyTyped (parseLam e)
        rest t
  where
    rest t =
      do
        reserved simplyTyped "::"
        t' <- parseType 0 e
        return (Ann t t')
parseITerm 2 e =
      do
        t <- parseITerm 3 e
        ts <- many (parseCTerm 3 e)
        return (foldl (:@:) t ts)
parseITerm 3 e =
      do
        x <- identifier simplyTyped
        case findIndex (== x) e of
          Just n  -> return (Bound n)
          Nothing -> return (Free (Global x))
  <|> parens simplyTyped (parseITerm 0 e)

parseCTerm :: Int -> [String] -> CharParser () CTerm
parseCTerm 0 e =
      parseLam e
  <|> fmap Inf (parseITerm 0 e)
parseCTerm p e =
      try (parens simplyTyped (parseLam e))
  <|> fmap Inf (parseITerm p e)

parseLam :: [String] -> CharParser () CTerm
parseLam e =
      do reservedOp simplyTyped "\\"
         xs <- many1 (identifier simplyTyped)
         reservedOp simplyTyped "->"
         t <- parseCTerm 0 (reverse xs ++ e)
         --  reserved simplyTyped "."
         return (iterate Lam t !! length xs)
parseIO :: String -> CharParser () a -> String -> IO (Maybe a)
parseIO f p x = case P.parse (whiteSpace simplyTyped >> p >>= \ x -> eof >> return x) f x of
                  Left e  -> putStrLn (show e) >> return Nothing
                  Right r -> return (Just r)
