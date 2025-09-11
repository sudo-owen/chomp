import { getFS } from "./utils.js";
import { typeData } from "./type-data.js";

document.addEventListener("DOMContentLoaded", function () {
  // Init filesystem APIs (if available)
  getFS().then(async (fs) => {
    // Elements
    const movesTable = document.getElementById("moves-table");
    const movesFileInput = document.getElementById("moves-file-input");
    const exportMovesBtn = document.getElementById("export-moves-btn");
    const addMoveBtn = document.getElementById("add-move-btn");

    // Add event listener for keyboard shortcuts
    document.addEventListener("keydown", function(event) {
      // Check for Ctrl+S (or Cmd+S on Mac)
      if ((event.ctrlKey || event.metaKey) && event.key === 's') {
        event.preventDefault(); // Prevent browser's save dialog

        // Check which tab is active
        const activeTab = document.querySelector(".tab.active");
        if (activeTab && activeTab.dataset.tab === "moves") {
          exportToCsv(); // Save moves data as CSV instead of JS
        }
      }
    });

    // Add save indicator
    const saveIndicator = document.createElement("span");
    saveIndicator.id = "moves-save-indicator";
    saveIndicator.textContent = "●";
    saveIndicator.style.color = "#4CAF50";
    saveIndicator.style.marginLeft = "8px";
    saveIndicator.style.opacity = "0";
    saveIndicator.title = "All changes saved";

    // Add the indicator next to export buttons
    exportMovesBtn.parentElement.appendChild(saveIndicator);

    let hasUnsavedChanges = false;

    function markUnsavedChanges() {
      hasUnsavedChanges = true;
      saveIndicator.style.opacity = "1";
      saveIndicator.style.color = "#ff9800";
      saveIndicator.title = "Unsaved changes";
    }

    function markChangesSaved() {
      hasUnsavedChanges = false;
      saveIndicator.style.opacity = "1";
      saveIndicator.style.color = "#4CAF50";
      saveIndicator.title = "All changes saved";
      // Fade out after 2 seconds
      setTimeout(() => {
        saveIndicator.style.opacity = "0";
      }, 2000);
    }

    // Function to notify other components when moves data changes
    function notifyMovesDataUpdated() {
      // Dispatch custom event
      document.dispatchEvent(
        new CustomEvent("moves-data-updated", {
          detail: {
            data: data,
            columns: columns
          }
        })
      );
    }

    // Initialize with empty data
    let columns = [];
    let data = [];
    let monsFromCsv = [];

    // Load mons from csv
    await loadMonsFromCsv();

    // Try to load from moves.csv first using fetch
    try {
      const response = await fetch('moves.csv');
      if (response.ok) {
        const csvContent = await response.text();
        parseCSV(csvContent);
      } else {
        throw new Error('Failed to fetch CSV');
      }
    } catch (error) {
      console.log("Could not load moves.csv, using default data", error);
    }

    async function loadMonsFromCsv() {
      try {
        const response = await fetch('mons.csv');
        if (response.ok) {
          const csvContent = await response.text();
          const lines = csvContent.split(/\r\n|\n/);

          if (lines.length < 2) return [];

          // Skip header, parse data rows
          monsFromCsv = [];
          for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;

            const values = parseCsvLine(line);
            if (values[0]) { // If it has a name
              monsFromCsv.push({ Name: values[1] });
            }
          }
          return monsFromCsv;
        }
      } catch (error) {
        console.error("Error loading mons.csv:", error);
      }
    }

    // Function to parse CSV content
    function parseCSV(csvContent) {
      const lines = csvContent.split(/\r\n|\n/);

      // Extract headers
      const headers = lines[0].split(",").map(header => header.trim());

      // Set columns
      columns = headers
        .map(header => ({
          name: header,
          type: ["Power", "Accuracy", "Stamina", "Priority"].includes(header) ? "number" : "text",
          editable: true
        }));

      // Parse data
      data = [];
      for (let i = 1; i < lines.length; i++) {
        const line = lines[i].trim();
        if (!line) continue;

        const values = parseCsvLine(line);
        const rowData = {};

        // Process all columns
        headers.forEach((header, index) => {
          const value = values[index]?.trim() || "";

          // Store all data
          rowData[header] = value;

          // Convert number types for UI display, but preserve special values like "?"
          if (["Power", "Accuracy", "Stamina", "Priority"].includes(header)) {
            if (value === "?" || value === "") {
              rowData[header] = value;
            } else {
              const numValue = parseFloat(value);
              rowData[header] = isNaN(numValue) ? 0 : numValue;
            }
          }
        });

        data.push(rowData);
      }

      renderMovesTable();
    }

    // Helper function to properly parse CSV lines with quoted values
    function parseCsvLine(line) {
      const result = [];
      let current = "";
      let inQuotes = false;

      for (let i = 0; i < line.length; i++) {
        const char = line[i];

        if (char === '"') {
          if (inQuotes && i + 1 < line.length && line[i + 1] === '"') {
            // Double quotes inside quotes - add a single quote
            current += '"';
            i++;
          } else {
            // Toggle quote mode
            inQuotes = !inQuotes;
          }
        } else if (char === ',' && !inQuotes) {
          // End of field
          result.push(current);
          current = "";
        } else {
          current += char;
        }
      }

      // Add the last field
      result.push(current);
      return result;
    }

    // Add sorting variables
    let columnToSort = undefined;
    let columnDirection = false; // false for ascending, true for descending

    // Event listeners
    movesFileInput.addEventListener("change", handleFileImport);
    exportMovesBtn.addEventListener("click", exportToCsv);
    addMoveBtn.addEventListener("click", addRow);

    // Initialize table
    renderMovesTable();

    // Add header click events for sorting
    addHeaderSortEvents();

    function addHeaderSortEvents() {
      const headers = movesTable.querySelectorAll("thead th");
      headers.forEach((header, index) => {
        header.style.cursor = "pointer";
        header.onclick = function() {
          const columnName = columns[index].name;
          // Toggle sort direction if clicking the same column
          if (columnToSort === columnName) {
            columnDirection = !columnDirection;
          } else {
            columnToSort = columnName;
            columnDirection = false; // default to ascending
          }

          // Sort the data
          sortData(columnName, !columnDirection);
        };
      });
    }

    function sortData(columnName, ascending = true) {
      data.sort((a, b) => {
        let aValue = a[columnName];
        let bValue = b[columnName];

        // Handle null/undefined values
        if (aValue === undefined || aValue === null) aValue = "";
        if (bValue === undefined || bValue === null) bValue = "";

        // Check if we're sorting a numeric column
        const column = columns.find(col => col.name === columnName);
        if (column && column.type === "number") {
          // Convert to numbers for numeric comparison
          aValue = parseFloat(aValue) || 0;
          bValue = parseFloat(bValue) || 0;
          return ascending ? aValue - bValue : bValue - aValue;
        } else {
          // String comparison for text columns
          return ascending
            ? String(aValue).localeCompare(String(bValue))
            : String(bValue).localeCompare(String(aValue));
        }
      });

      // Re-render the table with sorted data
      renderMovesTable();
      markUnsavedChanges();
    }

    function renderMovesTable() {
      const movesTableBody = movesTable.querySelector("tbody");
      movesTableBody.innerHTML = "";

      // Map to store monster name to hue mapping
      const monsterHues = new Map();
      const hueMinDistance = 35; // Minimum distance between hues

      // Create a function to generate distinct colors from monster names
      const getMonsterColor = (monsterName) => {
        if (!monsterName) return "";

        // If we've already assigned a hue to this monster, use it
        if (monsterHues.has(monsterName)) {
          const hue = monsterHues.get(monsterName);
          return `hsla(${hue}, 30%, 50%, 0.5)`;
        }

        // Generate a new hue for this monster
        let hash = 0;
        for (let i = 0; i < monsterName.length; i++) {
          hash = monsterName.charCodeAt(i) * 23 + ((hash << 17) - hash);
        }
        hash = Math.abs(hash);

        // Generate initial hue (0-360)
        let hue = hash % 360;

        // Check if this hue is too close to existing ones
        let attempts = 0;
        const usedHues = Array.from(monsterHues.values());

        // Limit attempts to avoid infinite loops
        while (attempts < 5) {
          // Check distance to all used hues
          const tooClose = usedHues.some(usedHue => {
            const distance = Math.min(
              Math.abs(hue - usedHue),
              360 - Math.abs(hue - usedHue)
            );
            return distance < hueMinDistance;
          });

          if (!tooClose || usedHues.length === 0) {
            // This hue is distinct enough or it's the first one
            break;
          }

          // Try a new hue by rehashing
          hash = (hash * 17) + 23;
          hue = hash % 360;
          attempts++;
        }

        // Store the hue for this monster
        monsterHues.set(monsterName, hue);

        // Return a subtle HSL color
        return `hsla(${hue}, 30%, 50%, 0.5)`;
      };

      data.forEach((row, rowIndex) => {
        const tr = document.createElement("tr");

        // Apply subtle background color based on monster
        const monsterName = row["Mon"];
        if (monsterName) {
          tr.style.backgroundColor = getMonsterColor(monsterName);
        }

        columns.forEach((column) => {
          const td = document.createElement("td");
          td.dataset.row = rowIndex;
          td.dataset.column = column.name;

          if (column.name === "Mon") {
            // Create select dropdown
            const select = document.createElement("select");
            select.style.width = "100%";
            select.style.padding = "4px";
            select.style.backgroundColor = "transparent";
            select.style.border = "none";
            select.style.cursor = "pointer";
            select.style.color = "inherit";

            // Add empty option
            const emptyOption = document.createElement("option");
            emptyOption.value = "";
            emptyOption.textContent = "Select monster...";
            select.appendChild(emptyOption);

            // Use the cached monsFromCsv instead of defaultMonsterData
            monsFromCsv.forEach(monster => {
              if (monster.Name) {
                const option = document.createElement("option");
                option.value = monster.Name;
                option.textContent = monster.Name;
                if (monster.Name === row[column.name]) {
                  option.selected = true;
                }
                select.appendChild(option);
              }
            });

            // Handle change event
            select.addEventListener("change", (e) => {
              data[rowIndex][column.name] = e.target.value;
              markUnsavedChanges();
              notifyMovesDataUpdated();
            });

            // Add monster icon next to the select
            const container = document.createElement("div");
            container.style.display = "flex";
            container.style.alignItems = "center";
            container.style.gap = "8px";

            const img = document.createElement("img");
            const monsterName = (row[column.name] || "").toLowerCase();
            img.src = `imgs/${monsterName}_mini.gif`;
            img.alt = row[column.name] || "";
            img.style.width = "32x";
            img.style.imageRendering = "pixelated";
            img.onerror = () => img.style.display = "none";

            // Update image when selection changes
            select.addEventListener("change", (e) => {
              const newMonsterName = e.target.value.toLowerCase();
              img.src = `imgs/${newMonsterName}_mini.gif`;
              img.alt = e.target.value;
              img.style.display = ""; // Reset display in case it was hidden
            });

            container.appendChild(img);
            container.appendChild(select);
            td.appendChild(container);
          } else if (column.name === "Type") {
            // Create type dropdown
            const select = document.createElement("select");
            select.style.width = "100%";
            select.style.padding = "4px";
            select.style.backgroundColor = "transparent";
            select.style.border = "none";
            select.style.cursor = "pointer";
            select.style.color = "inherit"; // Add this line to inherit the td's text color

            // Add empty option
            const emptyOption = document.createElement("option");
            emptyOption.value = "";
            emptyOption.textContent = "Select type...";
            select.appendChild(emptyOption);

            // Add type options
            Object.entries(typeData).forEach(([type, info]) => {
              const option = document.createElement("option");
              option.value = type;
              option.textContent = `${info.emoji} ${type}`;
              option.style.backgroundColor = info.bgColor;
              option.style.color = info.textColor;
              if (type === row[column.name]) {
                option.selected = true;
                td.style.backgroundColor = info.bgColor;
                td.style.color = info.textColor;
                // Add these lines to set the select's colors to match the selected type
                select.style.backgroundColor = info.bgColor;
                select.style.color = info.textColor;
              }
              select.appendChild(option);
            });

            // Handle change event
            select.addEventListener("change", (e) => {
              const selectedType = e.target.value;
              const typeInfo = typeData[selectedType];

              // Update cell styling
              td.style.backgroundColor = selectedType ? typeInfo.bgColor : "";
              td.style.color = selectedType ? typeInfo.textColor : "";

              // Update data
              data[rowIndex][column.name] = selectedType;
              markUnsavedChanges();
              notifyMovesDataUpdated();
            });

            td.appendChild(select);
          } else if (column.name === "Class") {
            // Create class dropdown
            const select = document.createElement("select");
            select.style.width = "100%";
            select.style.padding = "4px";
            select.style.backgroundColor = "transparent";
            select.style.border = "none";
            select.style.cursor = "pointer";
            select.style.color = "inherit";

            // Add empty option
            const emptyOption = document.createElement("option");
            emptyOption.value = "";
            emptyOption.textContent = "Select class...";
            select.appendChild(emptyOption);

            // Add class options with emojis
            const classOptions = [
              { value: "Physical", emoji: "👊", bgColor: "#222", textColor: "#eee" },
              { value: "Special", emoji: "🌀", bgColor: "#222", textColor: "#eee" },
              { value: "Other", emoji: "✨", bgColor: "#222", textColor: "#eee" },
              { value: "Self", emoji: "🔄", bgColor: "#222", textColor: "#eee" }
            ];

            classOptions.forEach(option => {
              const optElement = document.createElement("option");
              optElement.value = option.value;
              optElement.textContent = `${option.emoji} ${option.value}`;
              optElement.style.backgroundColor = option.bgColor;
              optElement.style.color = option.textColor;

              if (option.value === row[column.name]) {
                optElement.selected = true;
                td.style.backgroundColor = option.bgColor;
                td.style.color = option.textColor;
                select.style.backgroundColor = option.bgColor;
                select.style.color = option.textColor;
              }

              select.appendChild(optElement);
            });

            // Handle change event
            select.addEventListener("change", (e) => {
              const selectedClass = e.target.value;
              const classInfo = classOptions.find(opt => opt.value === selectedClass);

              // Update cell styling
              td.style.backgroundColor = selectedClass ? classInfo.bgColor : "";
              td.style.color = selectedClass ? classInfo.textColor : "";

              // Update data
              data[rowIndex][column.name] = selectedClass;
              markUnsavedChanges();
              notifyMovesDataUpdated();
            });

            td.appendChild(select);
          } else {
            if (column.editable) {
              td.contentEditable = true;
              td.className = "editable";

              if (column.type === "number") {
                // Handle special values like "?" for numeric fields
                const value = row[column.name];
                if (value === "?" || value === "") {
                  td.textContent = value;
                } else {
                  td.textContent = value || 0;
                }
              } else {
                td.textContent = row[column.name] || "";
              }

              td.addEventListener("blur", updateData);
            } else {
              td.textContent = row[column.name] || "";
            }
          }

          tr.appendChild(td);
        });

        // Remove the delete button column
        // No actionsTd or deleteBtn added here

        movesTableBody.appendChild(tr);
      });
    }

    function updateData(event) {
      const td = event.target;
      const rowIndex = parseInt(td.dataset.row);
      const column = td.dataset.column;
      const value = td.textContent.trim();

      if (columns.find(col => col.name === column)?.type === "number") {
        // Handle special non-numeric values like "?" for numeric fields
        if (value === "?" || value === "") {
          data[rowIndex][column] = value;
        } else {
          const numValue = parseFloat(value);
          data[rowIndex][column] = isNaN(numValue) ? 0 : numValue;
        }
      } else {
        data[rowIndex][column] = value;
      }
      markUnsavedChanges();
      notifyMovesDataUpdated();
    }

    function addRow() {
      const newRow = {};

      columns.forEach((column) => {
        if (column.type === "number") {
          newRow[column.name] = 0;
        } else {
          newRow[column.name] = "";
        }
      });

      data.push(newRow);
      renderMovesTable();
      markUnsavedChanges();
      notifyMovesDataUpdated();
    }

    function handleFileImport(event) {
      const file = event.target.files[0];
      if (!file) return;

      const reader = new FileReader();
      reader.onload = function(e) {
        const text = e.target.result;
        const lines = text.split("\n");

        if (lines.length < 2) return;

        // Extract headers
        const headers = lines[0].split(",").map(header => header.trim());

        // Reset columns
        columns = headers.map(header => ({
          name: header,
          type: "text",
          editable: true
        }));

        // Parse data
        data = [];
        for (let i = 1; i < lines.length; i++) {
          const line = lines[i].trim();
          if (!line) continue;

          const values = line.split(",");
          const rowData = {};
          headers.forEach((header, index) => {
            const value = values[index]?.trim() || "";
            rowData[header] = columns[index].type === "number" ? parseFloat(value) || 0 : value;
          });
          data.push(rowData);
        }

        renderMovesTable();
        movesFileInput.value = "";
        notifyMovesDataUpdated();
      };
      reader.readAsText(file);
    }

    async function exportToCsv() {
      // Get all headers from the first data row
      const originalHeaders = Object.keys(data[0] || {});
      const csvHeaders = originalHeaders.join(",");
      
      const rows = data.map(row => {
        return originalHeaders.map(header => {
          let value = row[header] !== undefined ? row[header] : "";
          
          if (typeof value === "string" && (value.includes(",") || value.includes('"') || value.includes("\n"))) {
            value = `"${value.replace(/"/g, '""')}"`;
          }
          return value;
        }).join(",");
      });
      
      const csvContent = [csvHeaders, ...rows].join("\n");
      
      try {
        await fs.writeTextFile("moves.csv", csvContent, {
          dir: fs.BaseDirectory.Runtime,
        });
      } catch (error) {
        // Web fallback
        const blob = new Blob([csvContent], { type: "text/csv" });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = "moves-export.csv";
        a.click();
        window.URL.revokeObjectURL(url);
      }
      markChangesSaved();
      notifyMovesDataUpdated();
    }
  });
});
