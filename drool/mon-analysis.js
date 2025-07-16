import { typeData } from "./type-data.js";
import { loadMovesFromCsv, loadTypeData } from "./utils.js";

document.addEventListener("DOMContentLoaded", async function () {
  // Elements
  const maxDamageTable = document.getElementById("max-damage-table");
  const transposeTableCheckbox = document.getElementById("transpose-table");
  const monsterSelect = document.getElementById("monster-select");

  // Variables for damage table
  let data = [];
  let columns = [];
  let isTransposed = false; // for max damage table view

  // Variables for max damage table sorting
  let maxDamageColumnToSort = undefined; // index of the column to sort by
  let maxDamageDirection = false; // false for ascending, true for descending

  // Variables for move damage table sorting
  let moveDamageColumnToSort = undefined; // column name to sort by
  let moveDamageDirection = false; // false for ascending, true for descending

  // Variables for move damage calculation
  let movesData = await loadMovesFromCsv();
  let typeEffectivenessData = await loadTypeData();

  // Event listeners
  transposeTableCheckbox.addEventListener("change", function() {
    isTransposed = this.checked;
    document.getElementById("view-perspective").textContent =
      isTransposed ? "(Defender View)" : "(Attacker View)";
    renderMaxDamageTable();
  });
  monsterSelect.addEventListener("change", (e) => {
    if (e.target.value !== "") {
      calculateMonsterAnalysis(parseInt(e.target.value));
    } else {
      document.getElementById("analysis-results").innerHTML = "";
    }
  });

  // Listen for data updates from mon-stats.js
  document.addEventListener("monster-data-updated", function(event) {
    data = event.detail.data;
    columns = event.detail.columns;
    updateMonsterSelect();
    renderMaxDamageTable();
  });

  // Listen for moves data updates from mon-moves.js
  document.addEventListener("moves-data-updated", async function(event) {
    // Update moves data
    movesData = event.detail.data;
    // Re-render the damage table with the updated moves
    renderMaxDamageTable();

    // If a monster is currently selected, recalculate its analysis
    const selectedMonsterIndex = monsterSelect.value;
    if (selectedMonsterIndex !== "") {
      calculateMonsterAnalysis(parseInt(selectedMonsterIndex));
    }
  });

  function updateMonsterSelect() {
    const select = document.getElementById("monster-select");
    select.innerHTML = '<option value="">Select a mon</option>';

    data.forEach((monster, index) => {
      const option = document.createElement("option");
      option.value = index;
      option.textContent = monster.Name || "Unknown";
      select.appendChild(option);
    });

    // Set the first monster as the default if there are any monsters
    if (data.length > 0) {
      select.value = 0; // Select the first monster
      calculateMonsterAnalysis(0); // Calculate analysis for the first monster
    }
  }

  function calculateMonsterAnalysis(monsterIndex) {
    const defender = data[monsterIndex];
    const results = {
      moveDamage: []
    };

    // Calculate all damage values
    data.forEach((attacker) => {
      // Calculate damage for each of the attacker's moves against the defender
      const attackerMoves = getMovesForMonster(attacker.Name);
      if (attackerMoves.length > 0) {
        attackerMoves.forEach(move => {
          const moveDamage = calculateMoveDamage(move, attacker, defender);
          if (moveDamage) {
            results.moveDamage.push({
              ...moveDamage,
              attacker: attacker.Name
            });
          }
        });
      }
    });

    const stats = {
      moveDamage: results.moveDamage
    };

    displayAnalysisResults(stats, defender.Name);
  }

  // Function to get type effectiveness multiplier
  function getTypeEffectiveness(attackerType, defenderType1, defenderType2) {
    let type1Multiplier = typeEffectivenessData[attackerType][defenderType1];
    if (type1Multiplier == 5) {
      type1Multiplier = 0.5;
    }
    let type2Multiplier = defenderType2 === 'NA' ? 1 : typeEffectivenessData[attackerType][defenderType2];
    if (type2Multiplier == 5) {
      type2Multiplier = 0.5;
    }
    return type1Multiplier * type2Multiplier;
  }

  // Function to calculate damage for a move
  function calculateMoveDamage(move, attacker, defender) {
    // Skip if move has no power or power is '?'
    if (!move.Power || move.Power === '?' || move.Power === 0) {
      return null;
    }

    // Determine if physical or special move
    const isPhysical = move.Class === 'Physical';
    const isSpecial = move.Class === 'Special';

    // Skip if not a damaging move
    if (!isPhysical && !isSpecial) {
      return null;
    }

    // Get the relevant attack and defense stats
    const attackStat = isPhysical ? attacker.Attack : attacker.SpecialAttack;
    const defenseStat = isPhysical ? defender.Defense : defender.SpecialDefense;
    const attackStatName = isPhysical ? 'Attack' : 'Sp.Atk';
    const defenseStatName = isPhysical ? 'Defense' : 'Sp.Def';

    // Calculate base damage
    let baseDamage = (move.Power * attackStat) / defenseStat;

    // Apply type effectiveness
    const typeMultiplier = getTypeEffectiveness(move.Type, defender.Type1, defender.Type2);
    const damage = baseDamage * typeMultiplier;

    return {
      damage,
      baseDamage,
      moveName: move.Name,
      moveType: move.Type,
      moveClass: move.Class,
      typeMultiplier,
      power: move.Power,
      percentHp: (damage / defender.HP) * 100,
      attackStat,
      defenseStat,
      attackStatName,
      defenseStatName
    };
  }

  // Function to get all moves for a monster
  function getMovesForMonster(monsterName) {
    return movesData.filter(move => move.Mon === monsterName);
  }

  // Function to render the move damage table rows
  function renderMoveDamageRows(moves, tableElement) {
    const tbody = tableElement.querySelector('tbody');
    tbody.innerHTML = ''; // Clear existing rows

    // Get min/max values for color scaling
    const allDamageValues = moves.map(move => move.percentHp);
    const minDamage = Math.min(...allDamageValues);
    const maxDamage = Math.max(...allDamageValues);

    moves.forEach(move => {
      const row = document.createElement('tr');

      // Highlight rows with percentHp > 90%
      if (move.percentHp > 90) {
        row.classList.add('high-damage-row');
      } else {
        // Add color scaling for normal damage
        const getColorIntensity = (value) => {
          const normalized = (value - minDamage) / (maxDamage - minDamage);
          return Math.floor(normalized * 40);
        };
        row.style.backgroundColor = `rgba(255, 99, 71, ${getColorIntensity(move.percentHp)}%)`;
      }

      // Get type color
      const typeInfo = typeData[move.moveType] || { bgColor: '#333', textColor: '#fff', emoji: '' };

      // Create calculation formula
      const calculationHtml = `
        <span class="calculation-formula">
          (${move.power} Power × ${move.attackStat} ${move.attackStatName}) ÷ ${move.defenseStat} ${move.defenseStatName} × ${move.typeMultiplier}
        </span>
        <div class="calculation-steps">
          = ${move.damage.toFixed(1)}
        </div>
      `;

      row.innerHTML = `
        <td>${move.moveName}</td>
        <td style="background-color: ${typeInfo.bgColor}; color: ${typeInfo.textColor}">
          ${typeInfo.emoji} ${move.moveType}
        </td>
        <td>
          <div style="display: flex; align-items: center; gap: 4px;">
            <img src="imgs/${move.attacker.toLowerCase()}_mini.gif" alt="${move.attacker}"
                 style="width: 32px; image-rendering: pixelated;" onerror="this.style.display='none'">
            <span>${move.attacker}</span>
          </div>
        </td>
        <td>${calculationHtml}</td>
        <td>${move.damage.toFixed(1)}</td>
        <td>${move.percentHp.toFixed(1)}%</td>
      `;

      tbody.appendChild(row);
    });
  }

  function displayAnalysisResults(stats, monsterName) {
    const resultsDiv = document.getElementById("analysis-results");
    const monsterNameLower = monsterName.toLowerCase();

    resultsDiv.innerHTML = `
      <div class="analysis-header">
        <img src="imgs/${monsterNameLower}_mini.gif" alt="${monsterName}"
             onerror="this.style.display='none'">
        <h3>Analysis for ${monsterName}</h3>
      </div>
      <div class="analysis-grid">
      </div>
    `;

    // Add move damage section if we have move data
    if (stats.moveDamage && stats.moveDamage.length > 0) {
      const moveDamageSection = document.createElement('div');
      moveDamageSection.className = 'analysis-item move-damage-section';
      moveDamageSection.innerHTML = `<h4>Move Damage Analysis</h4>`;

      // Create a table for move damage
      const moveTable = document.createElement('table');
      moveTable.className = 'move-damage-table';
      moveTable.innerHTML = `
        <thead>
          <tr>
            <th>Move</th>
            <th class="sortable" data-sort="moveType">Type <span class="sort-indicator"></span></th>
            <th class="sortable" data-sort="attacker">From <span class="sort-indicator"></span></th>
            <th>Calculation</th>
            <th class="sortable" data-sort="damage">Damage <span class="sort-indicator"></span></th>
            <th class="sortable" data-sort="percentHp">% HP <span class="sort-indicator"></span></th>
          </tr>
        </thead>
        <tbody></tbody>
      `;

      // Add event listeners to sortable headers
      moveTable.querySelectorAll('th.sortable').forEach(header => {
        header.style.cursor = 'pointer';
        header.addEventListener('click', () => {
          const sortKey = header.dataset.sort;
          sortMoveDamageTable(stats.moveDamage, sortKey, moveTable);
        });
      });

      // Sort moves by percentHp (highest first) by default
      moveDamageColumnToSort = 'percentHp';
      moveDamageDirection = true;
      sortMoveDamageTable(stats.moveDamage, moveDamageColumnToSort, moveTable, true);

      // Initial render of the move damage table
      renderMoveDamageRows(stats.moveDamage, moveTable);

      moveDamageSection.appendChild(moveTable);
      resultsDiv.querySelector('.analysis-grid').appendChild(moveDamageSection);
    }
  }

  // Function to calculate the greatest %HP damage each monster can deal to every other monster
  function calculateMaxDamage() {
    const maxDamageData = [];

    // For each attacker
    data.forEach((attacker) => {
      const attackerData = {
        name: attacker.Name,
        damages: []
      };

      // For each defender
      data.forEach((defender) => {
        // Calculate move damage if available
        let maxMoveDamage = 0;
        let maxMoveName = "";
        let maxMoveClass = "";
        let maxMoveType = "";
        let maxTypeMultiplier = 0;
        const attackerMoves = getMovesForMonster(attacker.Name);

        if (attackerMoves.length > 0) {
          attackerMoves.forEach(move => {
            const moveDamage = calculateMoveDamage(move, attacker, defender);
            if (moveDamage && moveDamage.percentHp > maxMoveDamage) {
              maxMoveDamage = moveDamage.percentHp;
              maxMoveName = move.Name;
              maxMoveClass = move.Class;
              maxMoveType = move.Type;
              maxTypeMultiplier = moveDamage.typeMultiplier;
            }
          });
        }

        let greatestDamage = maxMoveDamage;
        let damageSource = `${maxMoveName} (${maxMoveClass})`;

        attackerData.damages.push({
          defenderName: defender.Name,
          percentHp: greatestDamage,
          source: damageSource,
          moveType: maxMoveType,
          moveClass: maxMoveClass,
          typeMultiplier: maxTypeMultiplier
        });
      });

      maxDamageData.push(attackerData);
    });

    return maxDamageData;
  }

  // Function to sort the max damage table
  function sortMaxDamageTable(columnIndex) {
    // Toggle direction if clicking the same column
    if (maxDamageColumnToSort === columnIndex) {
      maxDamageDirection = !maxDamageDirection;
    } else {
      maxDamageColumnToSort = columnIndex;
      maxDamageDirection = true; // Default to descending (highest damage first)
    }

    // Re-render the table with the new sorting
    renderMaxDamageTable();
  }

  // Function to sort the move damage table
  function sortMoveDamageTable(moves, columnName, tableElement, skipDirectionToggle = false) {
    // Toggle direction if clicking the same column
    if (moveDamageColumnToSort === columnName && !skipDirectionToggle) {
      moveDamageDirection = !moveDamageDirection;
    } else if (!skipDirectionToggle) {
      moveDamageColumnToSort = columnName;
      moveDamageDirection = true; // Default to descending (highest first)
    }

    // Update sort indicators in the table headers
    tableElement.querySelectorAll('th.sortable').forEach(header => {
      const indicator = header.querySelector('.sort-indicator');
      if (header.dataset.sort === moveDamageColumnToSort) {
        indicator.textContent = moveDamageDirection ? ' ▼' : ' ▲';
      } else {
        indicator.textContent = '';
      }
    });

    // Sort the moves array based on the selected column
    moves.sort((a, b) => {
      let valueA, valueB;

      // Handle different column types
      switch (columnName) {
        case 'moveType':
          valueA = a.moveType || '';
          valueB = b.moveType || '';
          return moveDamageDirection
            ? valueB.localeCompare(valueA)
            : valueA.localeCompare(valueB);

        case 'attacker':
          valueA = a.attacker || '';
          valueB = b.attacker || '';
          return moveDamageDirection
            ? valueB.localeCompare(valueA)
            : valueA.localeCompare(valueB);

        case 'damage':
          valueA = a.damage || 0;
          valueB = b.damage || 0;
          return moveDamageDirection
            ? valueB - valueA
            : valueA - valueB;

        case 'percentHp':
          valueA = a.percentHp || 0;
          valueB = b.percentHp || 0;
          return moveDamageDirection
            ? valueB - valueA
            : valueA - valueB;

        default:
          return 0;
      }
    });

    // Re-render the table with the sorted data
    renderMoveDamageRows(moves, tableElement);
  }

  // Function to render the max damage table
  function renderMaxDamageTable() {
    if (!data || data.length === 0) return;

    maxDamageTable.innerHTML = "";

    // Calculate max damage data
    const maxDamageData = calculateMaxDamage();

    // Create header row
    const headerRow = document.createElement("tr");
    const cornerCell = document.createElement("th");
    cornerCell.textContent = isTransposed ? "Def ↓ / Atk →" : "Atk ↓ / Def →";
    headerRow.appendChild(cornerCell);

    // Create headers for each monster (columns)
    const columnMonsters = isTransposed ? maxDamageData : data;
    columnMonsters.forEach((monster, colIndex) => {
      const th = document.createElement("th");
      th.style.cursor = "pointer";

      // Add click handler for sorting
      th.addEventListener("click", () => {
        sortMaxDamageTable(colIndex);
      });

      const headerContent = document.createElement("div");
      headerContent.style.display = "flex";
      headerContent.style.flexDirection = "column";
      headerContent.style.alignItems = "center";
      headerContent.style.gap = "4px";

      const img = document.createElement("img");
      const monsterName = isTransposed ? monster.name.toLowerCase() : monster.Name.toLowerCase();
      img.src = `imgs/${monsterName}_mini.gif`;
      img.alt = isTransposed ? monster.name : monster.Name;
      img.onerror = () => (img.style.display = "none");

      const nameSpan = document.createElement("span");
      let nameText = isTransposed
        ? `⚔️ ${monster.name}`
        : `🛡️ ${monster.Name}`;

      // Add sort indicator if this is the sorted column
      if (maxDamageColumnToSort === colIndex) {
        nameText += maxDamageDirection ? " \u25BC" : " \u25B2";
      }

      nameSpan.textContent = nameText;

      headerContent.appendChild(img);
      headerContent.appendChild(nameSpan);
      th.appendChild(headerContent);
      headerRow.appendChild(th);
    });

    maxDamageTable.appendChild(headerRow);

    // Get min/max values for color scaling
    const allDamageValues = [];
    maxDamageData.forEach(attacker => {
      attacker.damages.forEach(damage => {
        allDamageValues.push(damage.percentHp);
      });
    });

    const minDamage = Math.min(...allDamageValues);
    const maxDamage = Math.max(...allDamageValues);

    // Create data rows
    let rowMonsters = isTransposed ? data : maxDamageData;

    // Sort the rows if a column is selected for sorting
    if (maxDamageColumnToSort !== undefined) {
      rowMonsters = [...rowMonsters].sort((a, b) => {
        let valueA, valueB;

        if (isTransposed) {
          // When transposed, we need to find the damage from the specific attacker
          const attackerName = maxDamageData[maxDamageColumnToSort].name;
          const damageToA = maxDamageData.find(d => d.name === attackerName)
            .damages.find(d => d.defenderName === a.Name);
          const damageToB = maxDamageData.find(d => d.name === attackerName)
            .damages.find(d => d.defenderName === b.Name);

          valueA = damageToA ? damageToA.percentHp : 0;
          valueB = damageToB ? damageToB.percentHp : 0;
        } else {
          // Normal view - just get the damage to the specific defender
          valueA = a.damages[maxDamageColumnToSort].percentHp;
          valueB = b.damages[maxDamageColumnToSort].percentHp;
        }

        return maxDamageDirection ? valueB - valueA : valueA - valueB;
      });
    }

    rowMonsters.forEach((rowMonster, rowIndex) => {
      const tr = document.createElement("tr");

      // Row header with image and name
      const rowHeader = document.createElement("th");
      const headerContent = document.createElement("div");
      headerContent.style.display = "flex";
      headerContent.style.alignItems = "center";
      headerContent.style.gap = "8px";

      const img = document.createElement("img");
      const monsterName = isTransposed
        ? rowMonster.Name.toLowerCase()
        : rowMonster.name.toLowerCase();
      img.src = `imgs/${monsterName}_mini.gif`;
      img.alt = isTransposed ? rowMonster.Name : rowMonster.name;
      img.onerror = () => (img.style.display = "none");

      const nameSpan = document.createElement("span");
      nameSpan.textContent = isTransposed
        ? `🛡️ ${rowMonster.Name}`
        : `⚔️ ${rowMonster.name}`;

      headerContent.appendChild(img);
      headerContent.appendChild(nameSpan);
      rowHeader.appendChild(headerContent);
      tr.appendChild(rowHeader);

      // Create cells for each column
      if (isTransposed) {
        // Transposed view: rows are defenders, columns are attackers
        maxDamageData.forEach((attacker) => {
          const damageInfo = attacker.damages.find(d => d.defenderName === rowMonster.Name);
          if (damageInfo) {
            const td = document.createElement("td");
            // Create a structured display for the damage info
            const damageValue = document.createElement("div");
            damageValue.style.fontWeight = "bold";
            damageValue.textContent = `${damageInfo.percentHp.toFixed(1)}%`;

            // Create type badge and multiplier display
            const badgeContainer = document.createElement("div");
            badgeContainer.className = "damage-badge-container";

            // Extract move name from source for better display
            const moveName = damageInfo.source.split(' (')[0];
            const moveClass = damageInfo.moveClass || '';

            // Create move name element with enhanced styling
            const moveNameElement = document.createElement("div");
            moveNameElement.className = "move-name-display";
            moveNameElement.textContent = moveName;

            // Add type badge with multiplier if we have move type info
            if (damageInfo.moveType) {
              const typeInfo = typeData[damageInfo.moveType] || { bgColor: '#333', textColor: '#fff', emoji: '' };
              const typeBadge = document.createElement("span");
              typeBadge.className = "damage-type-badge";
              typeBadge.style.backgroundColor = typeInfo.bgColor;
              typeBadge.style.color = typeInfo.textColor;

              // Add emoji and type multiplier together
              let badgeContent = typeInfo.emoji;

              // Add multiplier right next to the type
              if (damageInfo.typeMultiplier) {
                const multiplierSpan = document.createElement("span");
                multiplierSpan.className = "damage-type-multiplier";
                multiplierSpan.textContent = `×${damageInfo.typeMultiplier}`;
                typeBadge.appendChild(document.createTextNode(badgeContent));
                typeBadge.appendChild(multiplierSpan);
              } else {
                typeBadge.textContent = badgeContent;
              }

              badgeContainer.appendChild(typeBadge);
            }

            // Create source info with class emoji paired with the text
            const sourceInfo = document.createElement("div");
            sourceInfo.style.fontSize = "0.85em";
            sourceInfo.style.color = "#aaa";

            // Add move class with emoji
            if (moveClass) {
              const classEmoji = moveClass === 'Physical' ? '👊' :
                              moveClass === 'Special' ? '🌀' : '✨';
              sourceInfo.innerHTML = `${classEmoji} ${moveClass}`;
            } else {
              sourceInfo.textContent = damageInfo.source.split('(')[1]?.replace(')', '') || '';
            }

            td.appendChild(damageValue);
            td.appendChild(moveNameElement);
            td.appendChild(badgeContainer);
            td.appendChild(sourceInfo);

            // Check if damage is above 90% for special styling
            if (damageInfo.percentHp > 90) {
              td.classList.add('high-damage-cell');
            } else {
              // Add color scaling for normal damage
              const getColorIntensity = (value) => {
                const normalized = (value - minDamage) / (maxDamage - minDamage);
                return Math.floor(normalized * 40);
              };
              td.style.backgroundColor = `rgba(255, 99, 71, ${getColorIntensity(damageInfo.percentHp)}%)`;
            }
            tr.appendChild(td);
          } else {
            const td = document.createElement("td");
            td.textContent = "N/A";
            tr.appendChild(td);
          }
        });
      } else {
        // Normal view: rows are attackers, columns are defenders
        rowMonster.damages.forEach((damageInfo) => {
          const td = document.createElement("td");
          // Create a structured display for the damage info
          const damageValue = document.createElement("div");
          damageValue.style.fontWeight = "bold";
          damageValue.textContent = `${damageInfo.percentHp.toFixed(1)}%`;

          // Create type badge and multiplier display
          const badgeContainer = document.createElement("div");
          badgeContainer.className = "damage-badge-container";

          // Extract move name from source for better display
          const moveName = damageInfo.source.split(' (')[0];
          const moveClass = damageInfo.moveClass || '';

          // Create move name element with enhanced styling
          const moveNameElement = document.createElement("div");
          moveNameElement.className = "move-name-display";
          moveNameElement.textContent = moveName;

          // Add type badge with multiplier if we have move type info
          if (damageInfo.moveType) {
            const typeInfo = typeData[damageInfo.moveType] || { bgColor: '#333', textColor: '#fff', emoji: '' };
            const typeBadge = document.createElement("span");
            typeBadge.className = "damage-type-badge";
            typeBadge.style.backgroundColor = typeInfo.bgColor;
            typeBadge.style.color = typeInfo.textColor;

            // Add emoji and type multiplier together
            let badgeContent = typeInfo.emoji;

            // Add multiplier right next to the type
            if (damageInfo.typeMultiplier) {
              const multiplierSpan = document.createElement("span");
              multiplierSpan.className = "damage-type-multiplier";
              multiplierSpan.textContent = `×${damageInfo.typeMultiplier}`;
              typeBadge.appendChild(document.createTextNode(badgeContent));
              typeBadge.appendChild(multiplierSpan);
            } else {
              typeBadge.textContent = badgeContent;
            }

            badgeContainer.appendChild(typeBadge);
          }

          // Create source info with class emoji paired with the text
          const sourceInfo = document.createElement("div");
          sourceInfo.style.fontSize = "0.85em";
          sourceInfo.style.color = "#aaa";

          // Add move class with emoji
          if (moveClass) {
            const classEmoji = moveClass === 'Physical' ? '👊' :
                            moveClass === 'Special' ? '🌀' : '✨';
            sourceInfo.innerHTML = `${classEmoji} ${moveClass}`;
          } else {
            sourceInfo.textContent = damageInfo.source.split('(')[1]?.replace(')', '') || '';
          }

          td.appendChild(damageValue);
          td.appendChild(moveNameElement);
          td.appendChild(badgeContainer);
          td.appendChild(sourceInfo);

          // Check if damage is above 90% for special styling
          if (damageInfo.percentHp > 90) {
            td.classList.add('high-damage-cell');
          } else {
            // Add color scaling for normal damage
            const getColorIntensity = (value) => {
              const normalized = (value - minDamage) / (maxDamage - minDamage);
              return Math.floor(normalized * 40);
            };
            td.style.backgroundColor = `rgba(255, 99, 71, ${getColorIntensity(damageInfo.percentHp)}%)`;
          }
          tr.appendChild(td);
        });
      }

      maxDamageTable.appendChild(tr);
    });

    // Add some styling to the table
    maxDamageTable.style.borderCollapse = "collapse";
    const cells = maxDamageTable.getElementsByTagName("td");
    for (let cell of cells) {
      cell.style.padding = "8px 10px";
      cell.style.border = "1px solid #ddd";
      cell.style.textAlign = "center";
      cell.style.minWidth = "80px";
    }
  }

  // Check if we need to initialize with existing data
  // This is for when the page loads and mon-stats.js has already loaded data
  if (window.monsterData && window.monsterData.data && window.monsterData.columns) {
    data = window.monsterData.data;
    columns = window.monsterData.columns;
    updateMonsterSelect();
    renderMaxDamageTable();
  }
});
