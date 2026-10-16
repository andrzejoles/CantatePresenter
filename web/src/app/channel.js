// @ts-check
// Kanał między oknem głównym a oknem projekcji (ta sama przeglądarka, ten sam adres).
// main → projector: {type: "state", state}; projector → main: {type: "hello"}, {type: "action", action}, {type: "size", width, height}.
export const CHANNEL_NAME = "cantate-presenter";
export const openChannel = () => new BroadcastChannel(CHANNEL_NAME);
