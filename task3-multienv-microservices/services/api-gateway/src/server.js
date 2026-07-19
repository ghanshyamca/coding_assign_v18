const { createApp } = require("./app");

const PORT = process.env.PORT || 3000;

createApp().listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`api-gateway listening on ${PORT}`);
});
