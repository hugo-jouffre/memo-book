(async () => {
  const dataLink = document.querySelector('link[rel="alternate"][type="application/json"]');
  if (!dataLink) return;

  try {
    const response = await fetch(dataLink.getAttribute('href'), { cache: 'no-cache' });
    if (!response.ok) {
      throw new Error(`Statut de réponse inattendu: ${response.status}`);
    }

    const payload = await response.json();
    window.mbkSampleData = payload;
    console.info('Données MemoBook chargées pour la prévisualisation.', payload);
  } catch (error) {
    console.warn('Impossible de charger data.json pour la prévisualisation.', error);
  }
})();
