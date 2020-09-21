<template>
  <div class="container">
    <b-tabs>
      <b-tab-item label="Topics">
        <b-field>
          <b-select placeholder="Select a topic" @input="onTopicSelected" :loading="isLoading">
            <option v-for="topic in topics" :key="topic" :value="topic">{{ topic }}</option>
          </b-select>
        </b-field>
        <div>
          <pre v-if="topicDetails">{{ formattedTopicDetails }}</pre>
        </div>
      </b-tab-item>

      <b-tab-item label="Groups">
        <b-field>
          <b-select placeholder="Select a group" @input="onGroupSelected" :loading="isLoading">
            <option v-for="group in groups" :key="group" :value="group">{{ group }}</option>
          </b-select>
        </b-field>
        <div>
          <pre v-if="groupDetails">{{ formattedGroupDetails }}</pre>
        </div>
      </b-tab-item>
    </b-tabs>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'KafkaInfo',
  data() {
    return {
      topics: [],
      groups: [],
      topicDetails: null,
      groupDetails: null,
      isLoading: true,
    };
  },
  async created() {
    try {
      this.topics = (await CRUDService.kafka.topics.getAll()).topics;
      this.groups = (await CRUDService.kafka.groups.getAll()).groups;
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading kafka infos!'),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    } finally {
      this.isLoading = false;
    }
  },
  computed: {
    formattedTopicDetails() {
      return JSON.stringify(this.topicDetails, null, 4);
    },
    formattedGroupDetails() {
      return JSON.stringify(this.groupDetails, null, 4);
    },
  },
  methods: {
    async onTopicSelected(topic) {
      try {
        this.isLoading = true;
        this.topicDetails = null;
        this.topicDetails = await CRUDService.kafka.topics.get({ topic });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading topic details!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async onGroupSelected(group) {
      try {
        this.isLoading = true;
        this.groupDetails = null;
        this.groupDetails = await CRUDService.kafka.groups.get({ group_id: group });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading group details!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
  },
};
</script>
