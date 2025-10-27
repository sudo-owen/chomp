
import { loadFullMonsFromCsv, loadMovesFromCsv, loadAbilitiesFromCsv } from "./utils.js";
import { typeData } from "./type-data.js";

document.addEventListener("DOMContentLoaded", async function () {
    // Load mon data from CSV
    const monsFromCsv = await loadFullMonsFromCsv();
    const movesData = await loadMovesFromCsv();
    const abilitiesData = await loadAbilitiesFromCsv();

    // Calculate max values for each stat
    const maxStats = {
        HP: Math.max(...monsFromCsv.map(mon => mon.HP)),
        Attack: Math.max(...monsFromCsv.map(mon => mon.Attack)),
        Defense: Math.max(...monsFromCsv.map(mon => mon.Defense)),
        SpecialAttack: Math.max(...monsFromCsv.map(mon => mon.SpecialAttack)),
        SpecialDefense: Math.max(...monsFromCsv.map(mon => mon.SpecialDefense)),
        Speed: Math.max(...monsFromCsv.map(mon => mon.Speed))
    };

    let monIndex = 0;

    // Create all monster elements but hide them initially
    createAllMonElements(monsFromCsv, maxStats, movesData);

    // Function to navigate to previous monster
    function goToPrevMon() {
        monIndex = (monIndex - 1 + monsFromCsv.length) % monsFromCsv.length;
        showActiveMon();
        updateUrlHash();
    }

    // Function to navigate to next monster
    function goToNextMon() {
        monIndex = (monIndex + 1 + monsFromCsv.length) % monsFromCsv.length;
        showActiveMon();
        updateUrlHash();
    }

    // Function to navigate to a specific mon by index
    function goToMon(index) {
        if (index >= 0 && index < monsFromCsv.length) {
            monIndex = index;
            showActiveMon();
            updateUrlHash();
        }
    }

    // Function to update URL hash with current mon index
    function updateUrlHash() {
        // Only update hash if we're on the mons tab
        const monsTabActive = document.querySelector(".tab[data-tab='mons']").classList.contains("active");
        if (monsTabActive) {
            window.history.replaceState(null, null, `#mons${monIndex}`);
        }
    }

    // Bind to prev/next buttons to update index
    document.querySelector("#prev-mon-btn").addEventListener("click", goToPrevMon);
    document.querySelector("#next-mon-btn").addEventListener("click", goToNextMon);

    // Add keyboard navigation with arrow keys when Guide tab is active
    document.addEventListener("keydown", (event) => {
        // Only handle arrow keys when the Guide tab is active
        const monsTabActive = document.querySelector(".tab[data-tab='mons']").classList.contains("active");
        if (monsTabActive) {
            if (event.key === "ArrowLeft") {
                goToPrevMon();
                event.preventDefault(); // Prevent scrolling
            } else if (event.key === "ArrowRight") {
                goToNextMon();
                event.preventDefault(); // Prevent scrolling
            }
        }
    });

    // Listen for navigate-to-mon events from URL hash changes
    document.addEventListener("navigate-to-mon", (event) => {
        goToMon(event.detail.index);
    });

    // Check if there's a hash on initial load
    const initialHash = window.location.hash.substring(1);
    const monsMatch = initialHash.match(/^mons(\d+)$/);
    if (monsMatch) {
        const initialIndex = parseInt(monsMatch[1], 10);
        goToMon(initialIndex);
    } else if (!initialHash || initialHash === 'mons') {
        // Only show first mon and update hash if no hash or just #mons
        showActiveMon();
        updateUrlHash();
    } else {
        // For other hashes (like #stats), just show the first mon without updating hash
        showActiveMon();
    }

    // Create all monster elements but hide them
    function createAllMonElements(mons, maxStats, movesData) {
        const nameContainer = document.querySelector("#mon-container-name");
        const statsContainer = document.querySelector("#mon-container-stats");
        const abilitiesMovesContainer = document.querySelector("#mon-container-abilities-moves");

        // Clear containers
        nameContainer.innerHTML = '';
        statsContainer.innerHTML = '';
        abilitiesMovesContainer.innerHTML = '';

        mons.forEach((mon, idx) => {
            const monNameLower = mon.Name.toLowerCase();

            // Create name element
            const nameElement = document.createElement('div');
            nameElement.className = 'mon-name-element';
            nameElement.dataset.index = idx;
            nameElement.style.display = 'none'; // Hide initially
            nameElement.innerHTML = `
                <img src="imgs/${monNameLower}_mini.gif" alt="${mon.Name}"
                     onerror="this.style.display='none'">
                <div>${mon.Name}</div>
            `;

            // Create stats element
            const statsElement = document.createElement('div');
            statsElement.className = 'mon-stats-element';
            statsElement.dataset.index = idx;
            statsElement.style.display = 'none'; // Hide initially

            // Create abilities and moves element
            const abilitiesMovesElement = document.createElement('div');
            abilitiesMovesElement.className = 'mon-abilities-moves-element';
            abilitiesMovesElement.dataset.index = idx;
            abilitiesMovesElement.style.display = 'none'; // Hide initially

            // Add front and back images
            const monImagesHTML = `
                <div class="mon-sprites">
                    <img src="imgs/${monNameLower}_front.gif" alt="${mon.Name} front"
                         onerror="this.style.display='none'" class="mon-sprite">
                    <img src="imgs/${monNameLower}_back.gif" alt="${mon.Name} back"
                         onerror="this.style.display='none'" class="mon-sprite">
                </div>
            `;

            // Create stats grid
            const statsHTML = `
                <div class="stats-grid">
                    <div class="stat-row">
                        <span class="stat-label">HP</span>
                        <div class="stat-bar-container">
                            <div class="stat-bar-background">
                                <div class="stat-bar-fill hp-bar"
                                     style="width: ${(mon.HP / maxStats.HP) * 100}%"></div>
                            </div>
                            <span class="stat-value">${mon.HP}</span>
                        </div>
                    </div>
                    <div class="stat-row">
                        <span class="stat-label">ATK</span>
                        <div class="stat-bar-container">
                            <div class="stat-bar-background">
                                <div class="stat-bar-fill attack-bar"
                                     style="width: ${(mon.Attack / maxStats.Attack) * 100}%"></div>
                            </div>
                            <span class="stat-value">${mon.Attack}</span>
                        </div>
                    </div>
                    <div class="stat-row">
                        <span class="stat-label">𝞕ATK</span>
                        <div class="stat-bar-container">
                            <div class="stat-bar-background">
                                <div class="stat-bar-fill special-attack-bar"
                                     style="width: ${(mon.SpecialAttack / maxStats.SpecialAttack) * 100}%"></div>
                            </div>
                            <span class="stat-value">${mon.SpecialAttack}</span>
                        </div>
                    </div>
                    <div class="stat-row">
                        <span class="stat-label">DEF</span>
                        <div class="stat-bar-container">
                            <div class="stat-bar-background">
                                <div class="stat-bar-fill defense-bar"
                                     style="width: ${(mon.Defense / maxStats.Defense) * 100}%"></div>
                            </div>
                            <span class="stat-value">${mon.Defense}</span>
                        </div>
                    </div>
                    <div class="stat-row">
                        <span class="stat-label">𝞕DEF</span>
                        <div class="stat-bar-container">
                            <div class="stat-bar-background">
                                <div class="stat-bar-fill special-defense-bar"
                                     style="width: ${(mon.SpecialDefense / maxStats.SpecialDefense) * 100}%"></div>
                            </div>
                            <span class="stat-value">${mon.SpecialDefense}</span>
                        </div>
                    </div>
                    <div class="stat-row">
                        <span class="stat-label">SPD</span>
                        <div class="stat-bar-container">
                            <div class="stat-bar-background">
                                <div class="stat-bar-fill speed-bar"
                                     style="width: ${(mon.Speed / maxStats.Speed) * 100}%"></div>
                            </div>
                            <span class="stat-value">${mon.Speed}</span>
                        </div>
                    </div>
                </div>
            `;

            // Filter abilities for this monster
            const monAbilities = abilitiesData ? abilitiesData.filter(ability => ability.Mon === mon.Name) : [];

            // Create abilities section
            let abilitiesHTML = '';
            if (monAbilities && monAbilities.length > 0) {
                abilitiesHTML = `
                    <div class="mon-abilities-section">
                        ${monAbilities.map(ability => `
                            <div class="ability-card">
                                <div class="ability-name">${ability.Name || 'Unknown'}</div>
                                <div class="ability-effect">${ability.Effect || 'No effect'}</div>
                            </div>
                        `).join('')}
                    </div>
                `;
            }

            // Filter moves for this monster
            const monMoves = movesData ? movesData.filter(move => move.Mon === mon.Name) : [];

            // Create moves section
            let movesHTML = '';
            if (monMoves && monMoves.length > 0) {
                movesHTML = `
                    <div class="mon-moves-section">
                        <div class="moves-grid">
                            ${monMoves.map(move => {
                                const moveType = move.Type || '';
                                const moveClass = move.Class || '';
                                const typeInfo = typeData[moveType] || { bgColor: '#333', textColor: '#fff', emoji: '' };

                                // Determine class styling and emoji based on mon-moves.js
                                let classStyle = '';
                                let classEmoji = '';

                                if (moveClass === 'Physical') {
                                    classStyle = 'background-color: #C92112; color: white;';
                                    classEmoji = '👊'; // Physical emoji
                                } else if (moveClass === 'Special') {
                                    classStyle = 'background-color: #4F5870; color: white;';
                                    classEmoji = '🌀'; // Special emoji
                                } else if (moveClass === 'Other') {
                                    classStyle = 'background-color: #8C888C; color: white;';
                                    classEmoji = '✨'; // Other emoji
                                } else if (moveClass === 'Self') {
                                    classStyle = 'background-color: #8C888C; color: white;';
                                    classEmoji = '🔄'; // Self emoji
                                }

                                return `
                                    <div class="move-card">
                                        <div class="move-header">
                                            <span class="move-name">${move.Name || 'Unknown'}</span>
                                            <span class="move-type" style="background-color: ${typeInfo.bgColor}; color: ${typeInfo.textColor};">
                                                ${typeInfo.emoji} ${moveType}
                                            </span>
                                        </div>
                                        <div class="move-details">
                                            <div class="move-stat move-class" style="${classStyle}">
                                                ${classEmoji} ${moveClass}
                                            </div>
                                            <div class="move-stat">
                                                <span class="stat-icon">⚔️</span> ${move.Power || '-'}
                                            </div>
                                            <div class="move-stat">
                                                <span class="stat-icon">🔋</span> ${move.Stamina || '-'}
                                            </div>
                                            <div class="move-stat">
                                                <span class="stat-icon">🎯</span> ${move.Accuracy || '-'}%
                                            </div>
                                        </div>
                                        ${move.DevDescription ? `<div class="move-description">${move.DevDescription}</div>` : ''}
                                    </div>
                                `;
                            }).join('')}
                        </div>
                    </div>
                `;
            }

            // Set HTML content for each container
            statsElement.innerHTML = monImagesHTML + statsHTML;
            abilitiesMovesElement.innerHTML = abilitiesHTML + movesHTML;

            // Add elements to containers
            nameContainer.appendChild(nameElement);
            statsContainer.appendChild(statsElement);
            abilitiesMovesContainer.appendChild(abilitiesMovesElement);
        });
    }

    // Show only the active monster
    function showActiveMon() {
        // Hide all elements
        document.querySelectorAll('.mon-name-element, .mon-stats-element, .mon-abilities-moves-element').forEach(el => {
            el.style.display = 'none';
        });

        // Show only the active elements
        const activeNameEl = document.querySelector(`.mon-name-element[data-index="${monIndex}"]`);
        const activeStatsEl = document.querySelector(`.mon-stats-element[data-index="${monIndex}"]`);
        const activeAbilitiesMovesEl = document.querySelector(`.mon-abilities-moves-element[data-index="${monIndex}"]`);

        if (activeNameEl) activeNameEl.style.display = 'flex';
        if (activeStatsEl) activeStatsEl.style.display = 'block';
        if (activeAbilitiesMovesEl) activeAbilitiesMovesEl.style.display = 'block';
    }
});
