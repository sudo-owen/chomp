# C.H.O.M.P. (credibly hackable on-chain monster pvp)

on-chain turn-based pvp battling game, (heavily) inspired by pokemon showdown x mugen

![ghouliath back img](drool/imgs/ghouliath_back.gif)
![ghouliath front img](drool/imgs/ghouliath_front.gif)

designed to be highly extensible!

write your own moves!

your own mons!

your own effects!

your own hooks!

general flow of the game is: 
- each turn, players simultaneously choose a move on their active mon.
- moves can alter stats, do damage, or generally mutate game state in some way.
- this continues until one player has all their mons KO'ed

(think normal pokemon style)

mechanical differences are:
- extensible engine, write your own Effects or Moves or Hooks
- far greater support for state-based moves / mechanics
- stamina-based resource system instead of PP for balancing moves

See [Architecture](ARCHITECTURE.md) for a deeper dive.

## Getting Started

This repo uses [foundry](https://book.getfoundry.sh/getting-started/installation).

To get started:

`forge install`

`forge test`

To get a sense for how the tests are set up, look at [Effect Test](https://github.com/sudo-owen/chomp/blob/main/test/effects/EffectTest.sol) for a more streamlined version.

## Main Components

### Engine.sol
Main entry point for creating/advancing Battles.
Handles executing moves to advance battle state.
Stores global state / data available to all players.

### CommitManager.sol
Main entry point for managing moves.
Allows users to commit/reveal moves for battles.
Stores commitment history.

### IMoveSet.sol
Interface for a Move, an available choice for a Mon.

### IEffect.sol
Interface for an Effect, which can mutate game state and manage its own state. Moves and Effects can attach new Effects to a game state.

## Game Flow
General flow of battle:
- p0 commits hash of a Move
- p1 reveals their choice
- p0 reveals their preimage
- execute to advance game state

During a player's turn, they can choose either a Move on their active Mon, or switch to a new Mon.
