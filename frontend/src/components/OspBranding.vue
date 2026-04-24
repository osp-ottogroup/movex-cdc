<template>
  <div>
    <span class="osp-gray has-text-weight-bold">M</span>
    <span class="osp-red has-text-weight-bold">O</span>
    <span class="osp-gray has-text-weight-bold">VEX</span>
    <span class="osp-gray osp-stroke has-text-weight-light">|</span>
    <span class="osp-gray ml-1  has-text-weight-light" >Change Data Capture</span>
  </div>
</template>

<style lang="scss" scoped>
@use '../variables' as vars;

.osp-red {
  color: vars.$osp-red;
}
.osp-gray {
  color: vars.$osp-gray;
}
.osp-stroke {
  position: relative;
  top: -0.05rem;
}
</style>
