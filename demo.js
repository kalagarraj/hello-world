// demo.js - shared demo function used by result.html
function demo(name) {
  // Simple processing: greet and show length; this is the function called by the result page
  if (typeof name !== 'string' || name.trim() === '') return 'No name provided';
  const trimmed = name.trim();
  return `Hello, ${trimmed}! Your name has ${trimmed.length} characters.`;
}

// Expose for UMD-style access on pages that include this script
window.demo = demo;
