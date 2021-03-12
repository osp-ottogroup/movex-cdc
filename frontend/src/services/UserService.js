import TokenService from '@/services/TokenService';

let user = null;

const getUser = () => {
  if (user === null) {
    user = {
      id: TokenService.getPayload().user_id,
      name: `${TokenService.getPayload().first_name} ${TokenService.getPayload().last_name}`,
      isAdmin: TokenService.getPayload().is_admin,
      canDeploy: TokenService.getPayload().can_deploy,
    };
  }
  return user;
};

export default { getUser };
