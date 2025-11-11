# unnamed battle game
tldr: onchain turn-based battling, think [pokemon showdown](https://play.pokemonshowdown.com/) meets [m.u.g.e.n.](https://en.wikipedia.org/wiki/Mugen_(game_engine))
extensible on-chain battle engine for custom characters / rulesets

## why
- i think it's something that should exist
- make an on-chain game that people can point to as an example of something nice
- import web3 ip in fun ways, take advantage of being open-source
- somewhat neutral skill-based game for the community
- get other people nerdsniped

## game engine overview

```
Rough engine flow:
- initiate game, call validator to ensure it's a valid game configuration
- pre-game external hook calls
- advance turn with p1 and p2 moves, validator ensures they are valid moves
- validator checks priority between p1 and p2
- pre-move state updates 
- call p1 and p2 moves to update state 
- post-move state updates
- post-turn validator check (e.g. for end of game conditions)
- post-turn external hook calls
- if game end: post-game external hook calls
```

## game flow
- turn-based pvp game
- borrows a lot from pokemon battle system
- 2 players (can have extensions for more, but probably needs engine overhaul)
- game ends when one player has no more monsters with health
- players select moves simultaneously, then resolve in priority order

instead of pp, use stamina/energy system to balance out stronger move selection.

(basically each monster has some max energy (probably standardize it to like 5), and moves consume energy (1/2/3), and monsters regen 1 energy per turn)

(similar to AP from [cassette beasts](https://www.cassettebeasts.com/) sorta)

## making a monster
- stats (health/attack/speed/defense/etc)
- moves (list of function selectors and targets)
- abilities 
- art (front/back sprite, maybe animations / attacking / hurt if we have the ability to add those)

Goal is for anyone to contribute a monster, add it to their list/ruleset, and then use it with other people (who also adopt the ruleset). Bring tcrs back :^)

General musings on roles for monsters:
- stall (force opponent to FF)
- sweep (glass cannon type build, rely on priority / damage to win)
- midrange (generally outvalue your opponent by trying to be Pareto on all fronts)
- subgames (e.g. final countdown in yugioh or helix pinnacle in mtg, some weird subgame, sorta like stall variant)

## game extensions

### NPCs
`Validator` contracts ensure that both players select valid moves (e.g. for normal pvp games, they would ensure correct commit/reveal flow), but can also be used to plug in NPCs. General NPC interface would take in the state of the last turn as input and return a new valid move as output.

This allows for a simple building block for people to build synchronous PvE scenarios (e.g. gym leaders in pokemon, dungeons, gauntlet, kaizo-style challenges, etc.).

Also sets up the infra for NPC vs NPC style gauntlets, 0xmonaco style. Bringing back GOFAI onchain :^)

### ELO
Can do some mixture of onchain identity / [eigenkarma](https://www.lesswrong.com/posts/Fu7bqAyCMjfcMzBah/eigenkarma-trust-at-scale) to track ladders on-chain. Sweaty people can have their ranked games.

### Betting
Game logic is on-chain so it's very trivial to handle wagering for both players. External hooks / game state being readable means can even have sidebets etc. etc.

## game modes

- constructed (both players create teams ahead of time)
- draft (teams are created in real-time from some shared pool)
- random (teams are randomly selected, with some high-level balancing)
- battle royale, round robin
- tournament structure 
