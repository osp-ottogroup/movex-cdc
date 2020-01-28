import HttpService from './HttpService';

const backendUrl = window.location.origin;

export default name => ({
  getAll: async () => (await HttpService.get(`${backendUrl}/${name}`)).data,
  get: async id => (await HttpService.get(`${backendUrl}/${name}/${id}`)).data,
  delete: async id => (await HttpService.delete(`${backendUrl}/${name}/${id}`)).data,
  update: async object => (await HttpService.put(`${backendUrl}/${name}/${object.id}`, object)).data,
  create: async object => (await HttpService.post(`${backendUrl}/${name}`, object)).data,
});
