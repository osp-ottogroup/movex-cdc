<template>
  <div>
    <div v-if="contactPerson !== ''" class="has-text-grey-light mb-1">
      If you have questions regarding this Instance of MOVEX Change Data Capture,
      so please contact <span class="has-text-grey">{{ contactPerson }}</span>.
    </div>
    <div class="has-text-grey-light">
      Follow <router-link to="information">this link</router-link> to get more information about this instance of MOVEX Change Data Capture.
    </div>
  </div>
</template>

<script>
export default {
  name: 'ContactPerson',
  props: {
    contactPerson: { type: String, default: '' },
  },
};
</script>
